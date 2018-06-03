/*!
 * The worker thread does thing like downloading tools and running
 * builds, so the main thread can respond to client requests in a
 * timely manner.
 */
module bs.workerThread;

import core = [core.exception, core.rt.thread];
import io = watt.io;

import builder = bs.builder;

/*!
 * Informs the caller if a work request was received.
 */
alias Status = i32;
enum : Status
{
	Ok,    //!< Work will start/has started on the request.
	Fail,  //!< The work failed.
	Busy,  //!< Request cannot be accepted, as a previous task is still processing.
}

/*!
 * Start the worker thread.  
 * The thread runs until the build server process terminates.
 */
fn start()
{
	gThread = core.vrt_thread_start_fn(loop);
	if (core.vrt_thread_error(gThread)) {
		throw new core.Exception(core.vrt_thread_error_message(gThread));
	}
}

/*!
 * Stop the worker thread, release associated resources.
 */
fn stop()
{
	changeTask(Task.Shutdown);
	if (gTask != Task.Shutdown) {
		io.error.writeln("Couldn't cleanly shutdown build server worker thread.");
		return;
	}
	core.vrt_thread_join(gThread);
	gThread = null;
}

/*!
 * Attempt to start building the project at `projectRoot`.  
 * @Param projectRoot The path to the directory that holds the 'battery.toml' file.
 * @Returns `Ok` if the build work will start, `Busy` otherwise.
 */
fn build(projectRoot: string, reportFunction: fn(Status)) Status
{
	if (gProjectRoot !is null) {
		return Busy;
	}
	gProjectRoot = projectRoot;
	gReportFunction = reportFunction;
	changeTask(Task.Build);
	return gTask == Task.Build ? Ok : Busy;
}

private:

//! The states this thread can be in.
enum Task
{
	Sleep,    //!< Wait until asked to do something. Initial state.
	Build,    //!< Build a project.
	Shutdown, //!< Stop working.
}

global gThread: core.vrt_thread*;  //!< Handle for the thread.
global gTask: Task;           //!< What the thread has been asked to do.
global gProjectRoot: string;  //!< What the thread has been asked to build.
global gReportFunction: fn(Status);

/*!
 * Try to change the current task to `newTask`.  
 * The previous task may still be pending, so the task may not change.
 */
fn changeTask(newTask: Task)
{
	if (gTask == Task.Sleep) {
		gTask = newTask;
	}
}

//! Dispatch to the handler for the current task.
fn loop()
{
	shutdown := false;
	while (!shutdown) {
		final switch (gTask) with (Task) {
		case Sleep: core.vrt_sleep(10); break;
		case Shutdown: shutdown = true; break;
		case Build:
			retval := builder.build(gProjectRoot);
			gReportFunction(retval ? Ok : Fail);
			gProjectRoot = null;
			gTask = Task.Sleep;
			break;
		}
	}
}
