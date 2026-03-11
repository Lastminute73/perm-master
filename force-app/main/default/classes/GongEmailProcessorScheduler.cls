/**
 * Schedulable class that kicks off the Gong email processing batch job.
 * Schedule via anonymous Apex:
 *   System.schedule('Gong Email Processor - Daily 2AM', '0 0 2 * * ?',
 *       new GongEmailProcessorScheduler());
 */
public with sharing class GongEmailProcessorScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Create the Run record to track this execution
        Gong_Processing_Run__c run = new Gong_Processing_Run__c(
            Run_Date__c = Datetime.now(),
            Status__c = 'In Progress'
        );
        insert run;

        // Determine batch size from config
        Gong_Processor_Config__mdt config = GongEmailProcessorHelper.getConfig();
        Integer batchSize = config != null && config.Batch_Size__c != null
            ? Integer.valueOf(config.Batch_Size__c) : 200;

        // Start with Tasks first (chains to Events in finish())
        GongEmailProcessorBatch taskBatch =
            new GongEmailProcessorBatch(
                GongEmailProcessorBatch.ActivityType.TASK_TYPE, run.Id
            );
        Database.executeBatch(taskBatch, batchSize);
    }
}
