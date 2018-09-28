// src/main.d
// Main imports
import parser;
import tangler;
import weaver;
import util;
import globals;
import std.stdio;
import std.file;
import std.string;
import std.process;
import std.regex;
import std.conv;


// getLinenums function
Line[][string] getLinenums(Block[string] codeblocks, string blockName,
                 string rootName, Line[][string] codeLinenums) 
{
    Block block = codeblocks[blockName];

    if (block.commentString != "") 
    {
        codeLinenums[rootName] ~= new Line("comment", "", 0);
    }

    foreach (lineObj; block.lines) 
    {
        string line = lineObj.text;
        string stripLine = strip(line);
        if (stripLine.startsWith("@{") && stripLine.endsWith("}")) 
        {
            auto index = stripLine.length - 1;
            auto newBlockName = stripLine[2..index];
            getLinenums(codeblocks, newBlockName, rootName, codeLinenums);
        } 
        else 
        {
            codeLinenums[rootName] ~= lineObj;
        }
    }
    codeLinenums[rootName] ~= new Line("", "", 0);

    return codeLinenums;
}

// lit function
void lit(string filename, string fileSrc) 
{
    Program p = new Program();
    p.file = filename;
    if (fileSrc.matchFirst("(\n|^)@book\\s*?(\n|$)")) 
    {
        isBook = true;
        p = parseProgram(p, fileSrc);
        if (p.chapters.length == 0) 
        {
            error(filename, 1, "This book has no chapters");
            return;
        }
    } 
    else 
    {
        Chapter c = new Chapter();
        c.file = filename;
        c.majorNum = 1; c.minorNum = 0;

        c = parseChapter(c, fileSrc);
        p.chapters ~= c;
    }

    if (!weaveOnly) tangle(p);
    if (!tangleOnly) weave(p);
    
    if (!noCompCmd && !tangleErrors && !weaveOnly) 
    {
        // Check for compiler errors
        Line[][string] codeLinenums;
        
        Block[string] rootCodeblocks;
        Block[string] codeblocks;
        getCodeblocks(p, codeblocks, rootCodeblocks);
        
        foreach (b; rootCodeblocks) 
        {
            codeLinenums = getLinenums(codeblocks, b.name, b.name, codeLinenums);
        }
        string compilerCmd;
        string errorFormat;
        Command errorFormatCmd;
        foreach (cmd; p.commands) 
        {
            if (cmd.name == "@compiler") 
            {
                compilerCmd = cmd.args;
            } 
            else if (cmd.name == "@error_format") 
            {
                errorFormat = cmd.args;
                errorFormatCmd = cmd;
            }
        }
        if (p.chapters.length == 1) 
        {
            Chapter c = p.chapters[0];
            foreach (cmd; c.commands) 
            {
                if (cmd.name == "@compiler") 
                {
                    compilerCmd = cmd.args;
                } 
                else if (cmd.name == "@error_format") 
                {
                    errorFormat = cmd.args;
                    errorFormatCmd = cmd;
                }
            }
        }
        if (errorFormat is null) 
        {
            if (compilerCmd.indexOf("clang") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
            else if (compilerCmd.indexOf("gcc") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
            else if (compilerCmd.indexOf("g++") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
            else if (compilerCmd.indexOf("javac") != -1) { errorFormat = "%f:%l: %s: %m"; }
            else if (compilerCmd.indexOf("pyflakes") != -1) { errorFormat = "%f:%l:(%s:)? %m"; }
            else if (compilerCmd.indexOf("jshint") != -1) { errorFormat = "%f: line %l,%s, %m"; }
            else if (compilerCmd.indexOf("dmd") != -1) { errorFormat = "%f\\(%l\\):%s: %m"; }
        }
        if (errorFormat !is null) 
        {
            if (errorFormat.indexOf("%l") != -1 && errorFormat.indexOf("%f") != -1 && errorFormat.indexOf("%m") != -1) 
            {
                auto r = regex("");
                try 
                {
                    r = regex("^" ~ errorFormat.replaceAll(regex("%s"), ".*?")
                                                           .replaceAll(regex("%l"), "(?P<linenum>\\d+?)")
                                                           .replaceAll(regex("%f"), "(?P<filename>.*?)")
                                                           .replaceAll(regex("%m"), "(?P<message>.*?)") ~ "$");
                } 
                catch (Exception e) 
                {
                    error(errorFormatCmd.filename, errorFormatCmd.lineNum, "Regular expression error: " ~ e.msg);
                    return;
                }
        
                writeln(compilerCmd);
                auto output = executeShell(compilerCmd).output.split("\n");
                int i = 0;
        
                foreach (line; output) 
                {
                    auto matches = matchFirst(line, r);
        
                    if( !matches.empty) {
                    string linenum = matches["linenum"];
                    string fname = matches["filename"];
                    string message = matches["message"];
        
                    if (linenum != "" && fname != "") 
                    {
                        if (codeLinenums[fname].length > to!int(linenum)) 
                        {
                            auto codeline = codeLinenums[fname][to!int(linenum) - 1];
                            error(codeline.file, codeline.lineNum, message);
                        } 
                        else 
                        {
                            auto codeline = codeLinenums[fname][codeLinenums[fname].length - 2];
                            error(codeline.file, codeline.lineNum, message);
                        }
                    } 
                    else 
                    {
                        if (!(line == "" && i == output.length - 1)) writeln(line);
                    }
                    i++;
                    }
                }
            }
        }

    }
}


void main(in string[] args) 
{
    string[] files = [];
    // Parse the arguments
    for (int i = 1; i < args.length; i++) 
    {
        auto arg = args[i];
        if (arg == "--help" || arg == "-h") 
        {
            writeln(helpText);
            return;
        } 
        else if (arg == "--tangle" || arg == "-t") 
        {
            tangleOnly = true;
        } 
        else if (arg == "--weave" || arg == "-w") 
        {
            weaveOnly = true;
        }
        else if (arg == "--no-output" || arg == "-no") 
        {
            noOutput = true;
        }
        else if (arg == "--out-dir" || arg == "-odir") {
            if (i == args.length - 1) 
            {
                writeln("No output directory provided.");
                return;
            }
            outDir = args[++i];
        } 
        else if (arg == "--compiler" || arg == "-c") 
        {
            noCompCmd = false;
            noOutput = true;
        } 
        else if (arg == "--linenums" || arg == "-l") 
        {
            lineDirectives = true;
            if (i == args.length - 1) 
            {
                writeln("No line number string provided.");
                return;
            }
            lineDirectiveStr = args[++i];
        } 
        else if (arg == "--md-compiler") 
        {
            useMdCompiler = true;
            if (i == args.length - 1) 
            {
                writeln("No markdown compiler provided.");
                return;
            }
            mdCompilerCmd = args[++i];
        } 
        else if (arg == "--version" || arg == "-v") 
        {
            writeln("Literate version " ~ versionNum);
            writeln("Compiled by " ~ __VENDOR__ ~ " on " ~ __DATE__);
            return;
        } 
        else if (arg == "-") 
        {
            useStdin = true;
        } 
        else 
        {
            files ~= arg;
        }
    }

    // Run Literate
    if (files.length > 0) 
    {
        foreach (filename; files) 
        {
            if (!filename.exists()) 
            {
                writeln("File ", filename, " does not exist!");
                continue;
            }
            File f = File(filename);
            string fileSrc = readall(f);
    
            lit(filename, fileSrc);
        }
    } 
    else if (useStdin) 
    {
        string stdinSrc = readall();
        lit("stdin", stdinSrc);
    } 
    else  
    {
        writeln(helpText);
    }

}

