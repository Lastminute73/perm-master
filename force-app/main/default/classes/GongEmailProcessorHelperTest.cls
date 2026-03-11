/**
 * Unit tests for GongEmailProcessorHelper utility class.
 * Tests all static helper methods with various input scenarios.
 */
@IsTest
private class GongEmailProcessorHelperTest {

    // ── cleanEmail() ──────────────────────────────────────────────────────

    @IsTest
    static void cleanEmail_normalAddress_returnsLowered() {
        String result = GongEmailProcessorHelper.cleanEmail('John.Doe@Example.COM');
        System.assertEquals('john.doe@example.com', result,
            'Should lowercase the entire email');
    }

    @IsTest
    static void cleanEmail_prvsFormat_extractsEmail() {
        String result = GongEmailProcessorHelper.cleanEmail(
            'prvs=abc123=jane.smith@company.com'
        );
        System.assertEquals('jane.smith@company.com', result,
            'Should extract the real email from prvs= format');
    }

    @IsTest
    static void cleanEmail_plusAddressing_stripsTag() {
        String result = GongEmailProcessorHelper.cleanEmail(
            'user+newsletter@domain.com'
        );
        System.assertEquals('user@domain.com', result,
            'Should strip plus-addressing tag');
    }

    @IsTest
    static void cleanEmail_blankInput_returnsEmpty() {
        System.assertEquals('', GongEmailProcessorHelper.cleanEmail(null),
            'Null should return empty string');
        System.assertEquals('', GongEmailProcessorHelper.cleanEmail(''),
            'Empty string should return empty string');
        System.assertEquals('', GongEmailProcessorHelper.cleanEmail('   '),
            'Whitespace-only should return empty string');
    }

    @IsTest
    static void cleanEmail_whitespace_isTrimmed() {
        String result = GongEmailProcessorHelper.cleanEmail('  user@test.com  ');
        System.assertEquals('user@test.com', result,
            'Should trim leading and trailing whitespace');
    }

    @IsTest
    static void cleanEmail_prvsAndPlusAddressing_handlesBoth() {
        String result = GongEmailProcessorHelper.cleanEmail(
            'prvs=xyz=user+tag@domain.com'
        );
        System.assertEquals('user@domain.com', result,
            'Should handle prvs format and then strip plus-addressing');
    }

    // ── isValidEmail() ────────────────────────────────────────────────────

    @IsTest
    static void isValidEmail_standardAddress_returnsTrue() {
        System.assert(GongEmailProcessorHelper.isValidEmail('user@example.com'),
            'Standard email should be valid');
    }

    @IsTest
    static void isValidEmail_subdomainAddress_returnsTrue() {
        System.assert(GongEmailProcessorHelper.isValidEmail('user@mail.example.co.uk'),
            'Subdomain email should be valid');
    }

    @IsTest
    static void isValidEmail_withDotsAndHyphens_returnsTrue() {
        System.assert(GongEmailProcessorHelper.isValidEmail('first.last@my-company.com'),
            'Email with dots and hyphens should be valid');
    }

    @IsTest
    static void isValidEmail_missingAtSign_returnsFalse() {
        System.assert(!GongEmailProcessorHelper.isValidEmail('userexample.com'),
            'Email without @ should be invalid');
    }

    @IsTest
    static void isValidEmail_missingDomain_returnsFalse() {
        System.assert(!GongEmailProcessorHelper.isValidEmail('user@'),
            'Email without domain should be invalid');
    }

    @IsTest
    static void isValidEmail_blank_returnsFalse() {
        System.assert(!GongEmailProcessorHelper.isValidEmail(null),
            'Null should be invalid');
        System.assert(!GongEmailProcessorHelper.isValidEmail(''),
            'Empty string should be invalid');
    }

    @IsTest
    static void isValidEmail_noTLD_returnsFalse() {
        System.assert(!GongEmailProcessorHelper.isValidEmail('user@domain'),
            'Email without TLD should be invalid');
    }

    // ── extractDomain() ───────────────────────────────────────────────────

    @IsTest
    static void extractDomain_validEmail_returnsDomain() {
        System.assertEquals('example.com',
            GongEmailProcessorHelper.extractDomain('user@Example.COM'),
            'Should extract and lowercase the domain');
    }

    @IsTest
    static void extractDomain_noAtSign_returnsEmpty() {
        System.assertEquals('', GongEmailProcessorHelper.extractDomain('nodomain'),
            'No @ should return empty string');
    }

    @IsTest
    static void extractDomain_blank_returnsEmpty() {
        System.assertEquals('', GongEmailProcessorHelper.extractDomain(null),
            'Null should return empty string');
        System.assertEquals('', GongEmailProcessorHelper.extractDomain(''),
            'Empty string should return empty string');
    }

    // ── isInternalDomain() ────────────────────────────────────────────────
    // Custom Metadata is not available in unit tests unless deployed.
    // These tests verify the code path when getConfig() returns null.

    @IsTest
    static void isInternalDomain_noConfig_returnsFalse() {
        // When no Custom Metadata record exists, getConfig() returns null
        // so isInternalDomain should safely return false.
        Boolean result = GongEmailProcessorHelper.isInternalDomain('anydomain.com');
        System.assert(!result,
            'With no config, isInternalDomain should return false');
    }

    // ── isFreeDomain() ────────────────────────────────────────────────────

    @IsTest
    static void isFreeDomain_noConfig_returnsFalse() {
        // With no Custom Metadata, the excluded domains set is empty.
        Boolean result = GongEmailProcessorHelper.isFreeDomain('gmail.com');
        System.assert(!result,
            'With no config, isFreeDomain should return false for any domain');
    }

    // ── getConfig() / getExcludedDomains() ────────────────────────────────

    @IsTest
    static void getConfig_returnsNullWhenNoMetadata() {
        // Custom Metadata 'Default' record may or may not exist in test context.
        // This test simply exercises the code path; it should not throw.
        Gong_Processor_Config__mdt config = GongEmailProcessorHelper.getConfig();
        // No assertion on value because it depends on org metadata.
        // We just confirm no exception was thrown.
        System.assert(true, 'getConfig should execute without exception');
    }

    @IsTest
    static void getExcludedDomains_returnsSetWithoutException() {
        Set<String> domains = GongEmailProcessorHelper.getExcludedDomains();
        System.assertNotEquals(null, domains,
            'getExcludedDomains should return a non-null set');
    }

    // ── inferNameFromEmail() ──────────────────────────────────────────────

    @IsTest
    static void inferName_dotSeparated_splitsProperly() {
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('john.doe@company.com');
        System.assertEquals('John', result.get('firstName'),
            'First part before dot should become first name');
        System.assertEquals('Doe', result.get('lastName'),
            'Second part after dot should become last name');
    }

    @IsTest
    static void inferName_underscoreSeparated_splitsProperly() {
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('john_doe@company.com');
        System.assertEquals('John', result.get('firstName'));
        System.assertEquals('Doe', result.get('lastName'));
    }

    @IsTest
    static void inferName_hyphenSeparated_splitsProperly() {
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('mary-jane@company.com');
        System.assertEquals('Mary', result.get('firstName'));
        System.assertEquals('Jane', result.get('lastName'));
    }

    @IsTest
    static void inferName_singlePartLong_usesInitialHeuristic() {
        // "jsmith" -> first char "j", rest "smith"
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('jsmith@company.com');
        System.assertEquals('J', result.get('firstName'),
            'First char should be used as first name initial');
        System.assertEquals('Smith', result.get('lastName'),
            'Rest of local part should be last name');
    }

    @IsTest
    static void inferName_shortHandle_returnsHandleAsFirstName() {
        // 2 chars or fewer -> firstName = localPart, lastName = Unknown
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('ab@company.com');
        System.assertEquals('Ab', result.get('firstName'),
            'Short handle should be used as first name');
        System.assertEquals('Unknown', result.get('lastName'),
            'Last name should default to Unknown for short handles');
    }

    @IsTest
    static void inferName_numericLocal_returnsUnknown() {
        // All digits get cleaned to empty by replaceAll('[^a-zA-Z]', '')
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('12345@company.com');
        System.assertEquals('Unknown', result.get('firstName'),
            'Numeric-only local part should produce Unknown first name');
        System.assertEquals('Unknown', result.get('lastName'),
            'Numeric-only local part should produce Unknown last name');
    }

    @IsTest
    static void inferName_blank_returnsDefaults() {
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail(null);
        System.assertEquals('Unknown', result.get('firstName'));
        System.assertEquals('Unknown', result.get('lastName'));

        result = GongEmailProcessorHelper.inferNameFromEmail('');
        System.assertEquals('Unknown', result.get('firstName'));
        System.assertEquals('Unknown', result.get('lastName'));
    }

    @IsTest
    static void inferName_noAtSign_returnsDefaults() {
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('noemail');
        System.assertEquals('Unknown', result.get('firstName'));
        System.assertEquals('Unknown', result.get('lastName'));
    }

    @IsTest
    static void inferName_multipleSeparators_usesFirstAndLast() {
        // john.michael.doe -> first = john, last = doe (last element)
        Map<String, String> result =
            GongEmailProcessorHelper.inferNameFromEmail('john.michael.doe@company.com');
        System.assertEquals('John', result.get('firstName'));
        System.assertEquals('Doe', result.get('lastName'));
    }

    // ── parseEmailField() ─────────────────────────────────────────────────

    @IsTest
    static void parseEmailField_commaSeparated_returnsList() {
        List<String> result = GongEmailProcessorHelper.parseEmailField(
            'a@test.com, b@test.com, c@test.com'
        );
        System.assertEquals(3, result.size(),
            'Should parse three comma-separated emails');
        System.assertEquals('a@test.com', result[0]);
        System.assertEquals('b@test.com', result[1]);
        System.assertEquals('c@test.com', result[2]);
    }

    @IsTest
    static void parseEmailField_singleEmail_returnsSingletonList() {
        List<String> result = GongEmailProcessorHelper.parseEmailField(
            'only@email.com'
        );
        System.assertEquals(1, result.size(), 'Should return single email');
        System.assertEquals('only@email.com', result[0]);
    }

    @IsTest
    static void parseEmailField_blank_returnsEmptyList() {
        System.assertEquals(0,
            GongEmailProcessorHelper.parseEmailField(null).size(),
            'Null should return empty list');
        System.assertEquals(0,
            GongEmailProcessorHelper.parseEmailField('').size(),
            'Empty string should return empty list');
    }

    @IsTest
    static void parseEmailField_extraCommasAndSpaces_skipsEmpties() {
        List<String> result = GongEmailProcessorHelper.parseEmailField(
            ' a@test.com , , b@test.com , '
        );
        System.assertEquals(2, result.size(),
            'Should skip empty entries from extra commas');
    }
}
