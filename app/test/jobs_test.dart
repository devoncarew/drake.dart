
library jobs_test;

import 'dart:async';

import '../packages/unittest/unittest.dart';
import '../lib/jobs.dart';

main() {
  group('jobs', () {
    test('schedule', () {
      JobManager jobManager = new JobManager();
      
      Future future = jobManager.onChange.take(5).toList().then((List<JobManagerEvent> events) {
        JobManagerEvent e = events.removeAt(0);
        expect(true, e.started);
        
        e = events.removeAt(0);
        expect(e.progress, equals(0.0));

        e = events.removeAt(0);
        expect(e.progress, equals(0.1));

        e = events.removeAt(0);
        expect(e.progress, equals(1.0));

        e = events.removeAt(0);
        expect(true, e.finished);
      });
      
      MockJob job = new MockJob();
      jobManager.schedule(job);
      
      expect(future, completes);
    });    
  });
}

class MockJob extends Job {
  MockJob() : super("Mock job");
  
  Future<Job> run(ProgressMonitor monitor) {
    monitor.start("Mock job...", 10);
    
    return new Future(() {
      monitor.worked(1);
      monitor.done();
      
      return this;
    });    
  }

}

