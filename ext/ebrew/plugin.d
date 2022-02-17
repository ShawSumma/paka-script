module ext.ebrew.plugin;

import ext.ebrew.parse;

import purr.io;
import purr.srcloc;
import purr.ast.ast;
import purr.plugin.plugin;
import purr.plugin.plugins;

Parser parser;

Node parseEbrew(SrcLoc loc)
{
    parser.state = new ParseState(loc.src);
    return parser.readTopLevel;
}

shared static this()
{
    parser = new Parser();
    thisPlugin.addPlugin;
}

Plugin thisPlugin()
{
    Plugin plugin = new Plugin;
    plugin.parsers["ebrew"] = &parseEbrew;
    return plugin;
}
