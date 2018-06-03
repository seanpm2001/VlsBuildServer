module main;

import watt = [watt.io, watt.path];
import json = watt.json;
import lsp = vls.lsp;
import workerThread =bs.workerThread;
import builder = bs.builder;
static import build;

private global gBuildManager: build.Manager;
private global gPendingBuilds: build.Build[string];

fn main(args: string[]) i32
{
	if (args[1] == "--test") {
		return builder.test();
	}

	workerThread.start();
	scope (exit) workerThread.stop();

	gBuildManager = new build.Manager(watt.getExecDir());

	fn handle(msg: lsp.LspMessage) bool
	{
		ro := new lsp.RequestObject(msg.content);
		handleRequest(ro);
		return true;
	}

	while (lsp.listen(handle, watt.input)) {
	}

	return 0;
}

fn handleRequest(ro: lsp.RequestObject)
{
	if (ro.methodName != "workspace/executeCommand") {
		return;
	}
	command := lsp.getStringKey(ro.params, "command");
	if (command != "vls.buildProject") {
		return;
	}
	buildProject(ro);
}

fn buildProject(ro: lsp.RequestObject)
{
	arguments := lsp.getArrayKey(ro.params, "arguments");
	if (arguments.length == 0) {
		return;
	}
	if (arguments[0].type() != json.DomType.Object) {
		return;
	}
	fspath := lsp.getStringKey(arguments[0], "fsPath");
	btoml := lsp.getBatteryToml(fspath);
	if (btoml is null) {
		return;
	}
	buildPath := watt.dirName(btoml);
	if (p := buildPath in gPendingBuilds) {
		if (!p.completed) {
			lsp.send(lsp.buildVlsBuildPendingNotification(buildPath));
			return;
		}
	}
	gPendingBuilds[buildPath] = gBuildManager.spawnBuild(buildPath);
}
