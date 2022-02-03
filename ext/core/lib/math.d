module ext.core.lib.math;

import purr.dynamic;
import purr.base;
import core.stdc.stdlib;
import core.runtime;
import std.algorithm;
import std.array;
import std.conv;
import std.random;
import std.math;
import purr.io;

template Bind1(alias func, string name) {
    Dynamic Bind1(Args args) {
        if (args.length != 1) {
            throw new Exception("function " ~ name ~ ": wanted 1 arg but got " ~ args.length.to!string ~ "");
        }
        return dynamic(func(args[0].as!double));
    }
}

template Bind2(alias func, string name) {
    Dynamic Bind2(Args args) {
        if (args.length != 2) {
            throw new Exception("function " ~ name ~ ": wanted 2 args but got " ~ args.length.to!string ~ "");
        }
        return dynamic(func(args[0].as!double, args[1].as!double));
    }
}

template Bind2fi(alias func, string name) {
    Dynamic Bind2fi(Args args) {
        if (args.length != 2) {
            throw new Exception("function " ~ name ~ ": wanted 2 args but got " ~ args.length.to!string ~ "");
        }
        double n = args[1].as!double;
        if (n % 1 != 0)
        {
            throw new Exception("function " ~ name ~ ": 2nd argument should be an integer");
        }
        return dynamic(func(args[0].as!double, cast(int) n));
    }
}

template BindPair1(alias func, string name) {
    Pair BindPair1() {
        return FunctionPair!(Bind1!(func, name))(name);
    }
}

template BindPair2(alias func, string name) {
    Pair BindPair2() {
        return FunctionPair!(Bind2!(func, name))(name);
    }
}

template BindPair2fi(alias func, string name) {
    Pair BindPair2fi() {
        return FunctionPair!(Bind2fi!(func, name))(name);
    }
}

Pair[] libmath()
{
    Pair[] ret;
    // ret ~= FunctionPair!libabs("abs");
    // ret ~= FunctionPair!libmin("min");
    // ret ~= FunctionPair!libmax("max");
    ret.addLib("inspect", lib2inspect);
    ret.addLib("mod", lib2mod);
    ret.addLib("cmp", lib2cmp);
    ret.addLib("pow", lib2pow);
    ret.addLib("round", lib2round);
    ret.addLib("trig", lib2trig);
    ret.addLib("const", lib2const);
    return ret;
}

Pair[] lib2const()
{
    Pair[] ret;
    ret ~= Pair("tau", PI);
    ret ~= Pair("pi", PI);
    ret ~= Pair("e", E);
    ret ~= Pair("sqrt2", SQRT2);
    ret ~= Pair("nlog2", LN2);
    ret ~= Pair("nlog10", LN10);
    ret ~= Pair("inf", double.infinity);
    ret ~= Pair("ninf", -double.infinity);
    ret ~= Pair("nan", double.nan);
    return ret;
}

Pair[] lib2inspect()
{
    Pair[] ret;
    ret ~= BindPair1!(isFinite, "finite?");
    ret ~= BindPair1!(isInfinity, "inf?");
    ret ~= BindPair1!(isNaN, "nan?");
    ret ~= BindPair1!(isNormal, "normal?");
    ret ~= BindPair1!(isSubnormal, "subnormal?");
    ret ~= BindPair1!(signbit, "signbit");
    ret ~= BindPair1!(isPowerOf2, "pow2?");
    return ret;
}

Pair[] lib2trig()
{
    Pair[] ret;
    ret ~= BindPair1!(sin, "sin");
    ret ~= BindPair1!(cos, "cos");
    ret ~= BindPair1!(tan, "tan");
    ret ~= BindPair1!(asin, "asin");
    ret ~= BindPair1!(acos, "acos");
    ret ~= BindPair1!(atan, "atan");
    ret ~= BindPair1!(sinh, "sinh");
    ret ~= BindPair1!(cosh, "cosh");
    ret ~= BindPair1!(tanh, "tanh");
    ret ~= BindPair1!(asinh, "asinh");
    ret ~= BindPair1!(acosh, "acosh");
    ret ~= BindPair1!(atanh, "atanh");
    ret ~= BindPair2!(atan2, "atan2");
    return ret;
}

Pair[] lib2round()
{
    Pair[] ret;
    ret ~= BindPair1!(ceil, "ceil");
    ret ~= BindPair1!(floor, "floor");
    ret ~= BindPair1!(round, "round");
    ret ~= BindPair1!(lround, "lround");
    ret ~= BindPair1!(trunc, "trunc");
    ret ~= BindPair1!(rint, "rint");
    ret ~= BindPair1!(lrint, "lrint");
    ret ~= BindPair1!(nearbyint, "nearbyint");
    ret ~= BindPair1!(rndtol, "rndtol");
    ret ~= BindPair2!(quantize, "quantize");
    return ret;
}

Pair[] lib2pow()
{
    Pair[] ret;
    ret ~= BindPair1!(sqrt, "sqrt");
    ret ~= BindPair1!(cbrt, "cbrt");
    ret ~= BindPair1!(exp, "exp");
    ret ~= BindPair1!(exp2, "exp2");
    ret ~= BindPair1!(expm1, "expm2");
    ret ~= BindPair1!(log, "log");
    ret ~= BindPair1!(log2, "log2");
    ret ~= BindPair1!(log10, "log10");
    ret ~= BindPair1!(logb, "logb");
    ret ~= BindPair1!(ilogb, "ilogb");
    ret ~= BindPair1!(log1p, "log1p");
    ret ~= BindPair1!(nextPow2, "pow2next");
    ret ~= BindPair1!(truncPow2, "pow2last");
    ret ~= BindPair2!(pow, "pow");
    ret ~= BindPair2fi!(ldexp, "ldexp");
    // ret ~= BindPair2fi!(frexp, "frexp");
    ret ~= BindPair2fi!(scalbn, "scalbn");
    return ret;
}

Pair[] lib2mod()
{
    Pair[] ret;
    ret ~= BindPair2!(fmod, "fmod");
    ret ~= BindPair2!(remainder, "remainder");
    return ret;
}

Dynamic isEqualOr(alias func)(Args args)
{
    double rel = 0.01;
    double abs = 0.00001;
    if (args.length >= 3)
    {
        if (args[2].isNil)
        {
            rel = args[2].as!double;
        }
    }
    if (args.length >= 4)
    {
        if (args[3].isNil)
        {
            abs = args[3].as!double;
        }
    }
    double v1 = args[0].as!double;
    double v2 = args[1].as!double;
    bool same = isClose(v1, v2, rel, abs);
    if (same || func(v1, v2))
    {
        return true.dynamic;
    }
    return false.dynamic;
}

Dynamic lib2cmp2eq(Args args) {
    return args.isEqualOr!((x, y) => false);
}

Dynamic lib2cmp2lte(Args args) {
    return args.isEqualOr!((x, y) => false);
}

Dynamic lib2cmp2gte(Args args) {
    return args.isEqualOr!((x, y) => false);
}

Pair[] lib2cmp()
{
    Pair[] ret;
    ret ~= BindPair2!(std.math.cmp, "cmp");
    ret ~= BindPair2!(isIdentical, "identical?");
    ret ~= FunctionPair!(lib2cmp2eq)("eq?");
    ret ~= FunctionPair!(lib2cmp2lte)("lte?");
    ret ~= FunctionPair!(lib2cmp2gte)("gte?");
    return ret;
}
