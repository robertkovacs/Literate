// src/tangler.d
import globals;
import std.string;
import std.stdio;
import parser;
import util;
import std.conv: to;

void tangle(Program p) 
{
    // The tangle function
    Block[string] rootCodeblocks;
    Block[string] codeblocks;
    
    getCodeblocks(p, codeblocks, rootCodeblocks);
    if (rootCodeblocks.length == 0) 
    {
        warn(p.file, 1, "No file codeblocks, not writing any code");
    }
    foreach (b; rootCodeblocks) 
    {
        string filename = b.name;
        File f;
        if (!noOutput) f = File(outDir ~ "/" ~ filename, "w");
        writeCode(codeblocks, b.name, f, filename, "");
        if (!noOutput) f.close();
    }

}

// The writeCode function
void writeCode(Block[string] codeblocks, string blockName, File file, string filename, string whitespace) 
{
    Block block = codeblocks[blockName];

    if (block.commentString != "") 
    {
        if (!noOutput)
        {
            file.writeln(whitespace ~ block.commentString.replace("%s", blockName));
        }
    }

    foreach (lineObj; block.lines) 
    {
        string line = lineObj.text;
        string stripLine = strip(line);
        if (stripLine.startsWith("@{") && stripLine.endsWith("}")) 
        {
            string newWS = leadingWS(line);
            auto index = stripLine.length - 1;
            auto newBlockName = stripLine[2..index];
            if (newBlockName == blockName) 
            {
                error(lineObj.file, lineObj.lineNum, "{" ~ blockName ~ "} refers to itself");
                tangleErrors = true;
                return;
            }
            if ((newBlockName in codeblocks) !is null) 
            {
                writeCode(codeblocks, newBlockName, file, filename, whitespace ~ newWS);
            } 
            else 
            {
                error(lineObj.file, lineObj.lineNum, "{" ~ newBlockName ~ "} does not exist");
                tangleErrors = true;
            }
        } 
        else 
        {
            if (!noOutput) 
            {
                if (lineDirectives) 
                {
                    if (lineDirectiveStr != "") 
                    {
                        file.writeln(lineDirectiveStr, " ", lineObj.lineNum);
                    } 
                    else 
                    {
                        file.writeln(block.commentString.replace("%s", to!string(lineObj.lineNum)));
                    }
                }
                file.writeln(whitespace ~ line);
            }
        }
    }
    if (!noOutput) file.writeln();
}


