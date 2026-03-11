// Schedule the Gong Email Processor to run daily at 2:00 AM
// Run this script via: sf apex run --file scripts/apex/scheduleGongProcessor.apex --target-org perm-siy-test

// First, abort any existing scheduled job with the same name
for (CronTrigger ct : [SELECT Id, CronJobDetail.Name FROM CronTrigger
                        WHERE CronJobDetail.Name = 'Gong Email Processor - Daily 2AM']) {
    System.abortJob(ct.Id);
    System.debug('Aborted existing job: ' + ct.Id);
}

// Schedule the new job
String cronExp = '0 0 2 * * ?'; // Every day at 2:00 AM
GongEmailProcessorScheduler scheduler = new GongEmailProcessorScheduler();
String jobId = System.schedule('Gong Email Processor - Daily 2AM', cronExp, scheduler);
System.debug('Scheduled Gong Email Processor with Job Id: ' + jobId);
