/**
 * Tests for GongAIAnalyzerQueueable.
 * Uses HttpCalloutMock to simulate the Anthropic Messages API response.
 * Tests extractJsonFromText() and the full queueable execution flow.
 */
@IsTest
private class GongAIAnalyzerQueueableTest {

    /**
     * Mock HTTP response class simulating a successful Anthropic Messages API response.
     */
    private class AnthropicMock implements HttpCalloutMock {
        private String emailToReturn;

        public AnthropicMock(String email) {
            this.emailToReturn = email;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            // Build a response matching the Anthropic Messages API format
            String aiJson = '[{'
                + '"email": "' + emailToReturn + '",'
                + '"cleaned_first_name": "John",'
                + '"cleaned_last_name": "Smith",'
                + '"quality_score": 85,'
                + '"is_real_contact": true,'
                + '"analysis": "Looks like a real business contact"'
                + '}]';

            // Wrap in the Anthropic Messages API envelope
            String responseBody = '{'
                + '"id": "msg_test123",'
                + '"type": "message",'
                + '"role": "assistant",'
                + '"content": [{'
                + '  "type": "text",'
                + '  "text": ' + JSON.serialize(aiJson)
                + '}],'
                + '"model": "claude-sonnet-4-20250514",'
                + '"stop_reason": "end_turn"'
                + '}';

            res.setBody(responseBody);
            return res;
        }
    }

    /**
     * Mock that returns a non-200 status to test error handling.
     */
    private class AnthropicErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": {"type": "server_error", "message": "Internal error"}}');
            return res;
        }
    }

    /**
     * Mock that wraps JSON in a markdown code block (common Claude behavior).
     */
    private class AnthropicCodeBlockMock implements HttpCalloutMock {
        private String emailToReturn;

        public AnthropicCodeBlockMock(String email) {
            this.emailToReturn = email;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            String aiJson = '```json\n[{'
                + '"email": "' + emailToReturn + '",'
                + '"cleaned_first_name": "Jane",'
                + '"cleaned_last_name": "Doe",'
                + '"quality_score": 92,'
                + '"is_real_contact": true,'
                + '"analysis": "Strong business email"'
                + '}]\n```';

            String responseBody = '{'
                + '"id": "msg_test456",'
                + '"type": "message",'
                + '"role": "assistant",'
                + '"content": [{'
                + '  "type": "text",'
                + '  "text": ' + JSON.serialize(aiJson)
                + '}],'
                + '"model": "claude-sonnet-4-20250514",'
                + '"stop_reason": "end_turn"'
                + '}';

            res.setBody(responseBody);
            return res;
        }
    }

    /**
     * Helper: creates the Run + Result records needed for AI processing.
     */
    private static Map<String, Object> createTestRecords(String email) {
        Account acct = new Account(Name = 'AI Test Account');
        insert acct;

        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'AI Processing'
        );
        insert run;

        Gong_Processing_Result__c result = new Gong_Processing_Result__c(
            Gong_Processing_Run__c = run.Id,
            Email__c = email,
            First_Name__c = 'John',
            Last_Name__c = 'Smith',
            Domain__c = GongEmailProcessorHelper.extractDomain(email),
            Account__c = acct.Id,
            Result_Type__c = 'New Contact',
            Status__c = 'Pending Review',
            AI_Processed__c = false
        );
        insert result;

        return new Map<String, Object>{
            'account' => acct,
            'run' => run,
            'result' => result
        };
    }

    // ── extractJsonFromText() ────────────────────────────────────────────

    @IsTest
    static void extractJsonFromText_markdownJsonBlock_extractsContent() {
        String input = 'Here is the analysis:\n```json\n[{"email":"test@test.com"}]\n```\nDone.';
        String result = GongAIAnalyzerQueueable.extractJsonFromText(input);
        System.assert(result.startsWith('['),
            'Should extract JSON array from markdown json block');
        System.assert(result.contains('"email"'),
            'Extracted JSON should contain the email field');
    }

    @IsTest
    static void extractJsonFromText_plainCodeBlock_extractsContent() {
        String input = 'Result:\n```\n[{"email":"test@test.com"}]\n```';
        String result = GongAIAnalyzerQueueable.extractJsonFromText(input);
        System.assert(result.startsWith('['),
            'Should extract JSON array from plain code block');
    }

    @IsTest
    static void extractJsonFromText_rawJsonArray_returnsAsIs() {
        String input = '[{"email":"test@test.com","quality_score":90}]';
        String result = GongAIAnalyzerQueueable.extractJsonFromText(input);
        System.assertEquals(input, result,
            'Raw JSON array should be returned as-is');
    }

    @IsTest
    static void extractJsonFromText_jsonWithSurroundingText_extractsArray() {
        String input = 'Here are the results: [{"email":"a@b.com"}] end of results';
        String result = GongAIAnalyzerQueueable.extractJsonFromText(input);
        System.assert(result.startsWith('['),
            'Should find and extract the JSON array from surrounding text');
        System.assert(result.endsWith(']'),
            'Extracted text should end with ]');
    }

    @IsTest
    static void extractJsonFromText_noJsonContent_returnsOriginal() {
        String input = 'No JSON here at all';
        String result = GongAIAnalyzerQueueable.extractJsonFromText(input);
        System.assertEquals(input, result,
            'Should return original text when no JSON found');
    }

    // ── Queueable Execution with Mock ────────────────────────────────────

    @IsTest
    static void execute_withValidMockResponse_updatesResults() {
        String testEmail = 'john.smith@testcorp.com';
        Map<String, Object> testData = createTestRecords(testEmail);
        Gong_Processing_Run__c run =
            (Gong_Processing_Run__c) testData.get('run');

        Test.setMock(HttpCalloutMock.class, new AnthropicMock(testEmail));

        Test.startTest();
        GongAIAnalyzerQueueable job = new GongAIAnalyzerQueueable(run.Id);
        System.enqueueJob(job);
        Test.stopTest();

        // Verify the result was updated with AI data
        Gong_Processing_Result__c updatedResult = [
            SELECT AI_Processed__c, AI_Cleaned_First_Name__c,
                   AI_Cleaned_Last_Name__c, AI_Quality_Score__c,
                   AI_Is_Real_Contact__c, AI_Analysis__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
            LIMIT 1
        ];

        System.assert(updatedResult.AI_Processed__c,
            'AI_Processed should be true after processing');
        System.assertEquals('John', updatedResult.AI_Cleaned_First_Name__c,
            'AI should have set cleaned first name');
        System.assertEquals('Smith', updatedResult.AI_Cleaned_Last_Name__c,
            'AI should have set cleaned last name');
        System.assertEquals(85, updatedResult.AI_Quality_Score__c,
            'AI quality score should be 85');
        System.assert(updatedResult.AI_Is_Real_Contact__c,
            'AI should mark as real contact');
    }

    @IsTest
    static void execute_withCodeBlockResponse_updatesResults() {
        String testEmail = 'jane.doe@testcorp.com';
        Map<String, Object> testData = createTestRecords(testEmail);
        Gong_Processing_Run__c run =
            (Gong_Processing_Run__c) testData.get('run');

        Test.setMock(HttpCalloutMock.class,
            new AnthropicCodeBlockMock(testEmail));

        Test.startTest();
        GongAIAnalyzerQueueable job = new GongAIAnalyzerQueueable(run.Id);
        System.enqueueJob(job);
        Test.stopTest();

        Gong_Processing_Result__c updatedResult = [
            SELECT AI_Processed__c, AI_Cleaned_First_Name__c,
                   AI_Quality_Score__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
            LIMIT 1
        ];

        System.assert(updatedResult.AI_Processed__c,
            'AI_Processed should be true');
        System.assertEquals('Jane', updatedResult.AI_Cleaned_First_Name__c,
            'Should parse name from code-block wrapped response');
        System.assertEquals(92, updatedResult.AI_Quality_Score__c,
            'Should parse score from code-block wrapped response');
    }

    @IsTest
    static void execute_withApiError_marksResultsAsProcessedWithError() {
        String testEmail = 'error.test@testcorp.com';
        Map<String, Object> testData = createTestRecords(testEmail);
        Gong_Processing_Run__c run =
            (Gong_Processing_Run__c) testData.get('run');

        Test.setMock(HttpCalloutMock.class, new AnthropicErrorMock());

        Test.startTest();
        GongAIAnalyzerQueueable job = new GongAIAnalyzerQueueable(run.Id);
        System.enqueueJob(job);
        Test.stopTest();

        Gong_Processing_Result__c updatedResult = [
            SELECT AI_Processed__c, AI_Analysis__c
            FROM Gong_Processing_Result__c
            WHERE Gong_Processing_Run__c = :run.Id
            LIMIT 1
        ];

        System.assert(updatedResult.AI_Processed__c,
            'AI_Processed should be true even on error (to avoid retry loop)');
        System.assert(updatedResult.AI_Analysis__c.contains('AI processing failed'),
            'AI_Analysis should contain error message');
    }

    @IsTest
    static void execute_noResults_updatesRunStatusToAIComplete() {
        // Create a run with no unprocessed results
        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'AI Processing'
        );
        insert run;

        Test.setMock(HttpCalloutMock.class, new AnthropicMock('dummy@test.com'));

        Test.startTest();
        GongAIAnalyzerQueueable job = new GongAIAnalyzerQueueable(run.Id);
        System.enqueueJob(job);
        Test.stopTest();

        Gong_Processing_Run__c updatedRun = [
            SELECT Status__c
            FROM Gong_Processing_Run__c
            WHERE Id = :run.Id
        ];

        System.assertEquals('AI Complete', updatedRun.Status__c,
            'Run status should be "AI Complete" when no results to process');
    }
}
