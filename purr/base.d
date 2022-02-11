module purr.base;

import std.algorithm;
import purr.io;
import std.conv;
import std.traits;
import purr.dynamic;
import purr.bytecode;
import purr.plugin.syms;
import purr.plugin.plugins;

Pair FunctionPair(alias func)(string name)
{
    return Pair(name, native!func);
}

struct Pair
{
    string name;
    Dynamic val;
    this(T)(string n, T v) 
    {
        name = n;
        val = v.dynamic;
    }
}

Table addLib(ref Pair[] pairs, string name, Pair[] lib)
{
    Mapping dyn = emptyMapping;
    foreach (entry; lib)
    {
        if (!entry.name.canFind('.'))
        {
            string newName = name ~ "." ~ entry.name;
            dyn[dynamic(entry.name)] = entry.val;
        }
    }
    Table ret = new Table(dyn);
    pairs ~= Pair(name, ret);
    return ret;
}
