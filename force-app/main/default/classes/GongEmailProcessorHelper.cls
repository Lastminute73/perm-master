/**
 * Utility class for Gong email processing.
 * All methods are static and pure (no DML/SOQL) for easy testing.
 */
public with sharing class GongEmailProcessorHelper {

    public static final String EMAIL_REGEX =
        '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$';

    private static final Pattern EMAIL_PATTERN = Pattern.compile(EMAIL_REGEX);
    private static final Pattern PRVS_PATTERN = Pattern.compile('^prvs=[^=]+=(.+)$');

    // Cached config - loaded once per transaction
    private static Gong_Processor_Config__mdt cachedConfig;
    private static Set<String> cachedExcludedDomains;

    public static Gong_Processor_Config__mdt getConfig() {
        if (cachedConfig == null) {
            cachedConfig = Gong_Processor_Config__mdt.getInstance('Default');
        }
        return cachedConfig;
    }

    public static Set<String> getExcludedDomains() {
        if (cachedExcludedDomains == null) {
            cachedExcludedDomains = new Set<String>();
            Gong_Processor_Config__mdt config = getConfig();
            if (config != null && String.isNotBlank(config.Excluded_Domains__c)) {
                for (String domain : config.Excluded_Domains__c.split(',')) {
                    String trimmed = domain.trim().toLowerCase();
                    if (String.isNotBlank(trimmed)) {
                        cachedExcludedDomains.add(trimmed);
                    }
                }
            }
        }
        return cachedExcludedDomains;
    }

    /**
     * Cleans an email address:
     * 1. Handles prvs=xxx=email format (Proofpoint bounce verification)
     * 2. Strips plus-addressing tags (user+tag@domain -> user@domain)
     * 3. Trims and lowercases
     */
    public static String cleanEmail(String rawEmail) {
        if (String.isBlank(rawEmail)) {
            return '';
        }

        String email = rawEmail.trim().toLowerCase();

        // Handle prvs=xxx=email format
        Matcher prvsMatcher = PRVS_PATTERN.matcher(email);
        if (prvsMatcher.matches()) {
            email = prvsMatcher.group(1);
        }

        // Handle user+tag@domain format
        if (email.contains('+') && email.contains('@')) {
            List<String> parts = email.split('@', 2);
            if (parts.size() == 2) {
                String localPart = parts[0];
                String domainPart = parts[1];
                if (localPart.contains('+')) {
                    localPart = localPart.substringBefore('+');
                    email = localPart + '@' + domainPart;
                }
            }
        }

        return email;
    }

    public static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        return EMAIL_PATTERN.matcher(email).matches();
    }

    public static String extractDomain(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return '';
        }
        return email.substringAfter('@').toLowerCase();
    }

    public static Boolean isInternalDomain(String domain) {
        Gong_Processor_Config__mdt config = getConfig();
        if (config == null || String.isBlank(config.Internal_Domain__c)) {
            return false;
        }
        return domain.equalsIgnoreCase(config.Internal_Domain__c.trim());
    }

    public static Boolean isFreeDomain(String domain) {
        return getExcludedDomains().contains(domain.toLowerCase());
    }

    /**
     * Infers first and last name from an email address.
     * Examples:
     *   john.doe@company.com -> First: John, Last: Doe
     *   john_doe@company.com -> First: John, Last: Doe
     *   jsmith@company.com -> First: J, Last: Smith (if > 2 chars)
     */
    public static Map<String, String> inferNameFromEmail(String email) {
        Map<String, String> result = new Map<String, String>{
            'firstName' => 'Unknown',
            'lastName' => 'Unknown'
        };

        if (String.isBlank(email) || !email.contains('@')) {
            return result;
        }

        String localPart = email.substringBefore('@');

        // Split by common separators: dot, underscore, hyphen
        List<String> parts = localPart.split('[._\\-]');

        String firstName;
        String lastName;

        if (parts.size() >= 2) {
            firstName = parts[0];
            lastName = parts[parts.size() - 1];
        } else if (localPart.length() > 2) {
            // Heuristic: first char is initial, rest is last name
            firstName = localPart.substring(0, 1);
            lastName = localPart.substring(1);
        } else {
            firstName = localPart;
            lastName = 'Unknown';
        }

        // Remove non-alpha characters
        firstName = firstName.replaceAll('[^a-zA-Z]', '');
        lastName = lastName.replaceAll('[^a-zA-Z]', '');

        // Fallback if cleaning removed everything
        if (String.isBlank(firstName)) {
            firstName = 'Unknown';
        }
        if (String.isBlank(lastName)) {
            lastName = 'Unknown';
        }

        result.put('firstName', firstName.capitalize());
        result.put('lastName', lastName.capitalize());
        return result;
    }

    /**
     * Parses a comma-separated email field into individual emails.
     */
    public static List<String> parseEmailField(String commaSeparatedEmails) {
        List<String> emails = new List<String>();
        if (String.isBlank(commaSeparatedEmails)) {
            return emails;
        }
        for (String email : commaSeparatedEmails.split(',')) {
            String trimmed = email.trim();
            if (String.isNotBlank(trimmed)) {
                emails.add(trimmed);
            }
        }
        return emails;
    }
}
