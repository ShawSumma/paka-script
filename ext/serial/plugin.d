module ext.serial.plugin;

import purr.io;
import purr.base;
import purr.dynamic;
import purr.plugin.plugin;
import purr.plugin.plugins;
import ext.serial.cons;

shared static this()
{
    thisPlugin.addPlugin;
}

Plugin thisPlugin()
{
    Plugin plugin = new Plugin;
    plugin.libs ~= FunctionPair!serialdumps("_serial_dumps");
    plugin.libs ~= FunctionPair!serialreads("_serial_reads");
    plugin.libs ~= FunctionPair!serialfreeze("_serial_freeze");
    plugin.libs ~= FunctionPair!serialthaw("_serial_thaw");
    Pair[] libs;
    libs ~= FunctionPair!serialdumps("dumps");
    libs ~= FunctionPair!serialreads("reads");
    libs ~= FunctionPair!serialfreeze("freeze");
    libs ~= FunctionPair!serialthaw("thaw");
    plugin.libs.addLib("serial", libs);
    return plugin;
}
