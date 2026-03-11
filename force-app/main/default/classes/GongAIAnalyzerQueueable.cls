/**
 * Queueable class that calls the Anthropic Claude API to analyze proposed new contacts.
 * Processes results in batches of 50 and self-chains until all are done.
 *
 * For each proposed contact, Claude:
 * - Cleans up names inferred from email addresses
 * - Assesses whether the email is a real business contact
 * - Provides a quality score (0-100)
 */
public with sharing class GongAIAnalyzerQueueable
    implements Queueable, Database.AllowsCallouts {

    private Id runId;

    private static final Integer RESULTS_PER_CALL = 50;

    public GongAIAnalyzerQueueable(Id runId) {
        this.runId = runId;
    }

    public void execute(QueueableContext qc) {
        Gong_Processor_Config__mdt config = GongEmailProcessorHelper.getConfig();

        // Query next batch of unprocessed "New Contact" results
        Integer batchSize = config != null && config.AI_Batch_Size__c != null
            ? Integer.valueOf(config.AI_Batch_Size__c) : RESULTS_PER_CALL;

        List<Gong_Processing_Result__c> results = [
            SELECT Id, Email__c, First_Name__c, Last_Name__c, Domain__c,
                   Account__c, Account__r.Name, Activity_Subject__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :runId
              AND Result_Type__c = 'New Contact'
              AND AI_Processed__c = false
            ORDER BY Id
            LIMIT :batchSize
        ];

        if (results.isEmpty()) {
            // All results processed - update run status
            update new Gong_Processing_Run__c(
                Id = runId,
                Status__c = 'AI Complete'
            );
            return;
        }

        try {
            // Build prompt and call API
            String prompt = buildPrompt(results);
            String responseBody = callAnthropicAPI(prompt, config);
            updateResultsWithAI(results, responseBody);
        } catch (Exception e) {
            // Mark results as processed with error so we don't retry forever
            for (Gong_Processing_Result__c r : results) {
                r.AI_Processed__c = true;
                r.AI_Analysis__c = 'AI processing failed: ' + e.getMessage();
            }
            update results;
        }

        // Re-enqueue for next batch
        if (!Test.isRunningTest()) {
            System.enqueueJob(new GongAIAnalyzerQueueable(runId));
        }
    }

    private String buildPrompt(List<Gong_Processing_Result__c> results) {
        List<Map<String, String>> contacts = new List<Map<String, String>>();
        for (Gong_Processing_Result__c r : results) {
            Map<String, String> c = new Map<String, String>();
            c.put('email', r.Email__c);
            c.put('inferred_first_name', r.First_Name__c);
            c.put('inferred_last_name', r.Last_Name__c);
            c.put('domain', r.Domain__c);
            c.put('account_name', r.Account__r != null ? r.Account__r.Name : '');
            c.put('meeting_subject', r.Activity_Subject__c != null
                ? r.Activity_Subject__c : '');
            contacts.add(c);
        }

        String contactsJson = JSON.serialize(contacts);

        return 'You are analyzing email contacts extracted from Gong meeting recordings '
             + 'that were synced to Salesforce. For each contact below, please:\n\n'
             + '1. CLEAN UP THE NAME: The first and last names were inferred from the '
             + 'email prefix (e.g., john.smith@company.com -> John Smith). Fix any '
             + 'obvious issues: proper capitalization, handle numeric suffixes, '
             + 'separate concatenated names, etc.\n\n'
             + '2. ASSESS QUALITY: Determine if this looks like a real business '
             + 'contact vs. a system/noreply/generic email. Consider:\n'
             + '   - Is the email a personal business email (john.doe@company.com) '
             + 'or generic (info@, support@, noreply@)?\n'
             + '   - Does the domain look like a real company?\n'
             + '   - Is the inferred name plausible as a real person\'s name?\n\n'
             + '3. SCORE: Give a quality score 0-100 where:\n'
             + '   - 80-100: High confidence real business contact\n'
             + '   - 50-79: Likely real but some uncertainty\n'
             + '   - 20-49: Uncertain, possibly generic\n'
             + '   - 0-19: Likely not a real person (noreply, info@, etc.)\n\n'
             + 'Return ONLY a JSON array with one object per contact, no other text:\n'
             + '[\n'
             + '  {\n'
             + '    "email": "original email",\n'
             + '    "cleaned_first_name": "Corrected First Name",\n'
             + '    "cleaned_last_name": "Corrected Last Name",\n'
             + '    "quality_score": 85,\n'
             + '    "is_real_contact": true,\n'
             + '    "analysis": "Brief explanation of assessment"\n'
             + '  }\n'
             + ']\n\n'
             + 'Contacts to analyze:\n' + contactsJson;
    }

    private String callAnthropicAPI(String prompt, Gong_Processor_Config__mdt config) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_API/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000); // 2 minutes

        String model = config != null && String.isNotBlank(config.AI_Model__c)
            ? config.AI_Model__c : 'claude-sonnet-4-20250514';

        Map<String, Object> body = new Map<String, Object>();
        body.put('model', model);
        body.put('max_tokens', 4096);

        List<Map<String, String>> messages = new List<Map<String, String>>();
        messages.add(new Map<String, String>{
            'role' => 'user',
            'content' => prompt
        });
        body.put('messages', messages);

        req.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new GongAIException(
                'Anthropic API returned status ' + res.getStatusCode()
                + ': ' + res.getBody().abbreviate(1000)
            );
        }

        return res.getBody();
    }

    private void updateResultsWithAI(
        List<Gong_Processing_Result__c> results, String responseBody
    ) {
        // Parse the Anthropic Messages API response
        Map<String, Object> apiResponse =
            (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> content = (List<Object>) apiResponse.get('content');
        Map<String, Object> textBlock = (Map<String, Object>) content[0];
        String text = (String) textBlock.get('text');

        // Extract JSON array from text
        text = extractJsonFromText(text);

        List<Object> aiResults = (List<Object>) JSON.deserializeUntyped(text);

        // Build map of email -> AI result
        Map<String, Map<String, Object>> aiResultsByEmail =
            new Map<String, Map<String, Object>>();
        for (Object obj : aiResults) {
            Map<String, Object> aiResult = (Map<String, Object>) obj;
            String email = ((String) aiResult.get('email')).toLowerCase();
            aiResultsByEmail.put(email, aiResult);
        }

        // Update records
        for (Gong_Processing_Result__c result : results) {
            Map<String, Object> aiResult =
                aiResultsByEmail.get(result.Email__c.toLowerCase());
            if (aiResult != null) {
                result.AI_Cleaned_First_Name__c =
                    (String) aiResult.get('cleaned_first_name');
                result.AI_Cleaned_Last_Name__c =
                    (String) aiResult.get('cleaned_last_name');
                result.AI_Quality_Score__c =
                    ((Decimal) aiResult.get('quality_score'));
                result.AI_Is_Real_Contact__c =
                    (Boolean) aiResult.get('is_real_contact');
                result.AI_Analysis__c =
                    (String) aiResult.get('analysis');
            }
            result.AI_Processed__c = true;
        }

        update results;
    }

    @TestVisible
    private static String extractJsonFromText(String text) {
        // Handle Claude wrapping JSON in ```json ... ``` blocks
        if (text.contains('```json')) {
            Integer startIdx = text.indexOf('```json') + 7;
            Integer endIdx = text.indexOf('```', startIdx);
            if (endIdx > startIdx) {
                return text.substring(startIdx, endIdx).trim();
            }
        } else if (text.contains('```')) {
            Integer startIdx = text.indexOf('```') + 3;
            Integer endIdx = text.indexOf('```', startIdx);
            if (endIdx > startIdx) {
                return text.substring(startIdx, endIdx).trim();
            }
        }
        // Try to find JSON array directly
        Integer startIdx = text.indexOf('[');
        Integer endIdx = text.lastIndexOf(']');
        if (startIdx >= 0 && endIdx > startIdx) {
            return text.substring(startIdx, endIdx + 1);
        }
        return text;
    }

    public class GongAIException extends Exception {}
}
