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
    Pair[] libs;
    libs ~= FunctionPair!serialdumps("dumps");
    libs ~= FunctionPair!serialreads("reads");
    plugin.libs.addLib("serial", libs);
    return plugin;
}
