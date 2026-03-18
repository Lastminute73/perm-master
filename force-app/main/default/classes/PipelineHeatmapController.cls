/**
 * PipelineHeatmapController
 *
 * Serves opportunity data for the repPipelineHeatmap LWC.
 * Supports a rolling 5-quarter window (Q-1 → Q+3) with configurable
 * fiscal year start month.
 *
 * View levels:
 *   - Rep       → single user's pipeline
 *   - Territory → all opps sharing a Territory__c value
 *   - Company   → all opps (no filter)
 *
 * @author  Lightning CRM Solutions
 * @version 2.0
 */
public with sharing class PipelineHeatmapController {

    // ───────────────────────────────────────────────────────────────────────────
    // Public Apex Methods
    // ───────────────────────────────────────────────────────────────────────────

    /**
     * Returns open + Closed Won Opportunities for a given user within a
     * rolling 5-quarter window (Q-1 through Q+3 relative to today).
     *
     * @param userId       SF User Id; defaults to the running user if blank
     * @param fyStartMonth First month of the fiscal year (1 = Jan … 12 = Dec)
     */
    @AuraEnabled(cacheable=true)
    public static List<OppWrapper> getOpportunities(String userId, Integer fyStartMonth) {
        String  uid  = String.isBlank(userId) ? UserInfo.getUserId() : userId;
        Integer fySM = validateFyMonth(fyStartMonth);

        Date windowStart = quarterBoundary(Date.today(), fySM, -1, true);
        Date windowEnd   = quarterBoundary(Date.today(), fySM,  3, false);

        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate, Amount, Probability,
                   Owner.Name, Territory__c
            FROM   Opportunity
            WHERE  OwnerId      = :uid
              AND  CloseDate   >= :windowStart
              AND  CloseDate   <= :windowEnd
              AND  (IsClosed    = false OR IsWon = true)
            WITH   USER_MODE
            ORDER BY CloseDate ASC
            LIMIT  2000
        ];

        return wrapOpps(opps);
    }

    /**
     * Returns open + Closed Won Opportunities for a given territory within
     * the rolling 5-quarter window.
     *
     * @param territory    Territory__c value to filter by
     * @param fyStartMonth First month of the fiscal year (1 = Jan … 12 = Dec)
     */
    @AuraEnabled(cacheable=true)
    public static List<OppWrapper> getOpportunitiesByTerritory(String territory, Integer fyStartMonth) {
        Integer fySM = validateFyMonth(fyStartMonth);

        Date windowStart = quarterBoundary(Date.today(), fySM, -1, true);
        Date windowEnd   = quarterBoundary(Date.today(), fySM,  3, false);

        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate, Amount, Probability,
                   Owner.Name, Territory__c
            FROM   Opportunity
            WHERE  Territory__c = :territory
              AND  CloseDate   >= :windowStart
              AND  CloseDate   <= :windowEnd
              AND  (IsClosed    = false OR IsWon = true)
            WITH   USER_MODE
            ORDER BY CloseDate ASC
            LIMIT  5000
        ];

        return wrapOpps(opps);
    }

    /**
     * Returns open + Closed Won Opportunities across the entire company
     * within the rolling 5-quarter window.
     *
     * @param fyStartMonth First month of the fiscal year (1 = Jan … 12 = Dec)
     */
    @AuraEnabled(cacheable=true)
    public static List<OppWrapper> getOpportunitiesByCompany(Integer fyStartMonth) {
        Integer fySM = validateFyMonth(fyStartMonth);

        Date windowStart = quarterBoundary(Date.today(), fySM, -1, true);
        Date windowEnd   = quarterBoundary(Date.today(), fySM,  3, false);

        List<Opportunity> opps = [
            SELECT Id, Name, StageName, CloseDate, Amount, Probability,
                   Owner.Name, Territory__c
            FROM   Opportunity
            WHERE  CloseDate   >= :windowStart
              AND  CloseDate   <= :windowEnd
              AND  (IsClosed    = false OR IsWon = true)
            WITH   USER_MODE
            ORDER BY CloseDate ASC
            LIMIT  10000
        ];

        return wrapOpps(opps);
    }

    /**
     * Returns distinct Territory__c values from Opportunities in the
     * current 5-quarter window. Used to populate the territory picker.
     *
     * @param fyStartMonth First month of the fiscal year (1 = Jan … 12 = Dec)
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getTerritories(Integer fyStartMonth) {
        Integer fySM = validateFyMonth(fyStartMonth);

        Date windowStart = quarterBoundary(Date.today(), fySM, -1, true);
        Date windowEnd   = quarterBoundary(Date.today(), fySM,  3, false);

        List<String> territories = new List<String>();
        for (AggregateResult ar : [
            SELECT Territory__c territory
            FROM   Opportunity
            WHERE  Territory__c != null
              AND  CloseDate   >= :windowStart
              AND  CloseDate   <= :windowEnd
              AND  (IsClosed    = false OR IsWon = true)
            WITH   USER_MODE
            GROUP BY Territory__c
            ORDER BY Territory__c ASC
        ]) {
            territories.add((String) ar.get('territory'));
        }
        return territories;
    }

    /**
     * Returns all active standard users for the rep picker (App Tab mode).
     */
    @AuraEnabled(cacheable=true)
    public static List<RepWrapper> getSalesReps() {
        List<User> users = [
            SELECT Id, Name, Title
            FROM   User
            WHERE  IsActive  = true
              AND  UserType  = 'Standard'
            WITH   USER_MODE
            ORDER BY Name ASC
            LIMIT  500
        ];
        List<RepWrapper> result = new List<RepWrapper>();
        for (User u : users) {
            result.add(new RepWrapper(u));
        }
        return result;
    }

    // ───────────────────────────────────────────────────────────────────────────
    // Private Helpers
    // ───────────────────────────────────────────────────────────────────────────

    private static Integer validateFyMonth(Integer m) {
        return (m != null && m >= 1 && m <= 12) ? m : 1;
    }

    private static List<OppWrapper> wrapOpps(List<Opportunity> opps) {
        List<OppWrapper> result = new List<OppWrapper>();
        for (Opportunity o : opps) {
            result.add(new OppWrapper(o));
        }
        return result;
    }

    /**
     * Computes the start (isStart=true) or end (isStart=false) boundary date
     * of the fiscal quarter that is `quarterOffset` quarters from today's FQ.
     *
     * Example (fyStartMonth=2, Feb FY):
     *   Q1 = Feb–Apr | Q2 = May–Jul | Q3 = Aug–Oct | Q4 = Nov–Jan
     */
    @TestVisible
    private static Date quarterBoundary(Date d, Integer fySM, Integer quarterOffset, Boolean isStart) {
        // Months elapsed since FY start (0–11)
        Integer mOffset = Math.mod(d.month() - fySM + 12, 12);
        // 0-indexed FQ within FY  (0=Q1, 1=Q2, 2=Q3, 3=Q4)
        Integer curQ    = mOffset / 3;
        // Calendar year the current FY started
        Integer fyYear  = (d.month() >= fySM) ? d.year() : d.year() - 1;

        // Apply offset, rolling FY year when we cross boundaries
        Integer tgtQ    = curQ + quarterOffset;
        Integer tgtYear = fyYear;
        while (tgtQ >= 4) { tgtQ -= 4; tgtYear++; }
        while (tgtQ <  0) { tgtQ += 4; tgtYear--; }

        // FQ start → calendar month (1-indexed)
        Integer tgtMonth   = fySM + (tgtQ * 3);
        Integer tgtYearAdj = tgtYear;
        while (tgtMonth > 12) { tgtMonth -= 12; tgtYearAdj++; }

        if (isStart) {
            return Date.newInstance(tgtYearAdj, tgtMonth, 1);
        }
        // Quarter end = day before the start of the following quarter
        Integer nextMonth = tgtMonth + 3;
        Integer nextYear  = tgtYearAdj;
        while (nextMonth > 12) { nextMonth -= 12; nextYear++; }
        return Date.newInstance(nextYear, nextMonth, 1).addDays(-1);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // Inner Wrapper Classes
    // ───────────────────────────────────────────────────────────────────────────

    public class OppWrapper {
        @AuraEnabled public String  id        { get; set; }
        @AuraEnabled public String  name      { get; set; }
        @AuraEnabled public String  stage     { get; set; }
        @AuraEnabled public String  closeDate { get; set; } // 'YYYY-MM-DD'
        @AuraEnabled public Decimal amount    { get; set; }
        @AuraEnabled public Decimal prob      { get; set; } // 0–100
        @AuraEnabled public String  ownerName { get; set; }
        @AuraEnabled public String  territory { get; set; }

        public OppWrapper(Opportunity o) {
            this.id        = o.Id;
            this.name      = o.Name;
            this.stage     = o.StageName;
            this.closeDate = String.valueOf(o.CloseDate);
            this.amount    = o.Amount      != null ? o.Amount      : 0;
            this.prob      = o.Probability != null ? o.Probability : 0;
            this.ownerName = o.Owner != null ? o.Owner.Name : '';
            this.territory = o.Territory__c;
        }
    }

    public class RepWrapper {
        @AuraEnabled public String id    { get; set; }
        @AuraEnabled public String name  { get; set; }
        @AuraEnabled public String title { get; set; }

        public RepWrapper(User u) {
            this.id    = u.Id;
            this.name  = u.Name;
            this.title = u.Title != null ? u.Title : '';
        }
    }
}
