// src/parser.d
// Parser imports
import globals;
import std.stdio;
import util;
import std.string: split, endsWith, startsWith, chomp, replace, strip;
import std.algorithm: canFind;
import std.regex: matchAll, matchFirst, regex, ctRegex, splitter;
import std.conv;
import std.path: extension;
import std.file;
import std.array;

// Classes
// Program class
class Program 
{
    public string title;
    public Command[] commands;
    public Chapter[] chapters;
    public string file;
    public string text;

    this() 
    {
        commands = [];
        chapters = [];
    }
}

// Chapter class
class Chapter 
{
    public string title;
    public Command[] commands;
    public Section[] sections;
    public string file;

    public int majorNum;
    public int minorNum;

    this() 
    {
        commands = [];
        sections = [];
    }

    string num() 
    {
        if (minorNum != 0) return to!string(majorNum) ~ "." ~ to!string(minorNum);        
        else return to!string(majorNum);  
    }
}

// Section class
class Section 
{
    public string title;
    public Command[] commands;
    public Block[] blocks;
    public int[6] num;
    public int level;

    this() 
    {
        commands = [];
        blocks = [];
    }

    string numToString() 
    {
        string numString;
        for(int i = 5; i >= 0; i--) 
        {
            if (numString == "" && num[i] == 0) continue;
            numString = to!string(num[i]) ~ (numString == "" ? "" : ".") ~ numString;
        }
        return numString;
    }
}

// Block class
class Block 
{
    public Line startLine;
    public string name;
    public bool isCodeblock;
    public bool isRootBlock;
    public Line[] lines;

    public string codeType;
    public string commentString;

    public Modifier[] modifiers;

    this() 
    {
        lines = [];
        modifiers = [];
    }

    string text() 
    {
        string text = "";
        foreach (line; lines) text ~= line.text ~ "\n";
        return text;
    }

    Block dup() 
    {
        Block b = new Block();
        b.startLine = startLine;
        b.name = name;
        b.isCodeblock = isCodeblock;
        b.codeType = codeType;
        b.commentString = commentString;
        b.modifiers = modifiers;

        foreach (Line l; lines) b.lines ~= l.dup();
        
        return b;
    }
}

// Command class
class Command 
{
    public string name;
    public string args;
    public int lineNum;
    public string filename;
}

// Line class
class Line 
{
    public string file;
    public int lineNum;
    public string text;

    this(string text, string file, int lineNum) 
    {
        this.text = text;
        this.file = file;
        this.lineNum = lineNum;
    }

    Line dup() 
    {
        return new Line(text, file, lineNum);
    }
}

// Change class
class Change 
{
    public string filename;
    public string[] searchText;
    public string[] replaceText;
    public int index;

    this() 
    {
        searchText = [];
        replaceText = [];
        index = 0;
    }
}


// Parse functions
// parseProgram function
Program parseProgram(Program p, string src) 
{
    string filename = p.file;
    bool hasChapters;

    string[] lines = src.split("\n");
    int lineNum;
    int majorNum;
    int minorNum;
    foreach (line; lines) 
    {
        lineNum++;

        if (line.startsWith("@title")) 
        {
            p.title = strip(line[6..$]);
        } 
        else if (line.startsWith("@book")) 
        {
            continue;
        } 
        else if (auto matches = matchFirst(line, regex(r"\[(?P<chapterName>.*)\]\((?P<filepath>.*)\)"))) 
        {
            if (matches["filepath"] == "") 
            {
                error(filename, lineNum, "No filepath for " ~ matches["chapterName"]);
                continue;
            }
            if (leadingWS(line).length > 0) 
            {
                minorNum++;
            } 
            else 
            {
                majorNum++;
                minorNum = 0;
            }
            Chapter c = new Chapter();
            c.file = matches["filepath"];
            c.title = matches["chapterName"];
            c.majorNum = majorNum;
            c.minorNum = minorNum;

            p.chapters ~= parseChapter(c, readall(File(matches["filepath"])));
            hasChapters = true;
        } 
        else 
        {
            p.text ~= line ~ "\n";
        }
    }

    return p;
}

// parseChapter function
Chapter parseChapter(Chapter chapter, string src) 
{
    // Initialize some variables
    string filename = chapter.file;
    string[] commands = ["@code_type", "@comment_type", "@compiler", "@error_format",
                         "@add_css", "@overwrite_css", "@colorscheme", "@include"];
    Section curSection;
    int[6] sectionNum = [0, 0, 0, 0, 0, 0];
    Block curBlock;
    Change curChange;
    bool inCodeblock = false;
    bool inSearchBlock = false;
    bool inReplaceBlock = false;

    // Increase section number
    void increaseSectionNum(int level) 
    {
        if (level > 5) 
        {
            throw new Exception("Levels higher than 5 are not supported in 'increaseSectionNum'");
        }
        for (int i = 5; i > level; i--) 
        {
            sectionNum[i] = 0;
        }
        sectionNum[level]++;
    }


    string[] blocks = [];

    string include(string file) 
    {
        if (file == filename) 
        {
            error(filename, 1, "Recursive include");
            return "";
        }
        if (!exists(file))
        {
            error(filename, 1, "File " ~ file ~ " does not exist");
            return "";
        }
        return readall(File(file));
    }

    // Handle the @include statements
    /* src = std.regex.replaceAll!(match => include(match[1]))(src, regex(`\n@include (.*)`)); */
    string[] linesStr = src.split("\n");
    Line[] lines;
    foreach (lineNum, line; linesStr) 
    {
        lines ~= new Line(line, filename, cast(int) lineNum+1);
    }

    for (int j = 0; j < lines.length; j++) 
    {
        auto lineObj = lines[j];
        filename = lineObj.file;
        auto lineNum = lineObj.lineNum;
        auto line = lineObj.text;

        if (strip(line).startsWith("//") && !inCodeblock) continue;
        
        // Parse the line
        if (!inCodeblock) 
        {
            // This might be a change block
            // Parse change block
            // Start a change block
            if (startsWith(line, "@change") && !startsWith(line, "@change_end")) 
            {
                curChange = new Change();
                curChange.filename = strip(line[7..$]);
                continue;
            } 
            else if (startsWith(line, "@replace")) 
            {
                // Begin the search block
                curChange.searchText ~= "";
                curChange.replaceText ~= "";
                inReplaceBlock = false;
                inSearchBlock = true;
                continue;
            } 
            else if (startsWith(line, "@with")) 
            {
                // Begin the replace block and end the search block
                inReplaceBlock = true;
                inSearchBlock = false;
                continue;
            } 
            else if (startsWith(line, "@end")) 
            {
                // End the replace block
                inReplaceBlock = false;
                inSearchBlock = false;
                // Increment the number of changes
                curChange.index++;
                continue;
            } 
            else if (startsWith(line, "@change_end")) 
            {
                // Apply all the changes
                string text = readall(File(curChange.filename));
                foreach (i; 0 .. curChange.index) 
                {
                    text = text.replace(curChange.searchText[i], curChange.replaceText[i]);
                }
                Chapter c = new Chapter();
                c.file = curChange.filename;
                // We can ignore these, but they need to be initialized
                c.title = "";
                c.majorNum = -1;
                c.minorNum = -1;
                Chapter includedChapter = parseChapter(c, text);
                // Overwrite the current file's title and add to the commands and sections
                chapter.sections ~= includedChapter.sections;
                chapter.commands ~= includedChapter.commands;
                chapter.title = includedChapter.title;
                continue;
            }
            
            // Just add the line to the search or replace text depending
            else if (inSearchBlock) 
            {
                curChange.searchText[curChange.index] ~= line ~ "\n";
                continue;
            } 
            else if (inReplaceBlock) 
            {
                curChange.replaceText[curChange.index] ~= line ~ "\n";
                continue;
            }

            // Parse a command
            if (line.split().length > 1) 
            {
                if (commands.canFind(line.split()[0])) 
                {
                    Command cmd = new Command();
                    cmd.name = line.split()[0];
                    auto index = cmd.name.length;
                    cmd.args = strip(line[index..$]);
                    cmd.lineNum = lineNum;
                    cmd.filename = filename;
                    if (cmd.args == "none") cmd.args = "";
                    
                    if (cmd.name == "@include") 
                    {
                        Line[] includedLines;
                        string fileSrc = readall(File(cmd.args));
                        foreach (includedLineNum, includedLine; fileSrc.split("\n")) 
                        {
                            auto includedLineObj = new Line(includedLine, cmd.args, cast(int) includedLineNum + 1);
                            includedLines ~= includedLineObj;
                        }
                        if (includedLines.length > 0) 
                        {
                            lines = lines[0 .. lineNum] ~ includedLines ~ lines[lineNum .. $];
                        }
                    }
            
                    if (curSection is null) chapter.commands ~= cmd;       
                    else curSection.commands ~= cmd;
                }
            }

            // Parse a title command
            if (startsWith(line, "@title")) 
            {
                chapter.title = strip(line[6..$]);
            }

            // Parse a section definition
            else if (line.startsWith("#")) 
            {
                if (curBlock !is null && !curBlock.isCodeblock) 
                {
                    if (strip(curBlock.text()) != "") 
                    {
                        curSection.blocks ~= curBlock;
                    }
                } else if (curBlock !is null && curBlock.isCodeblock) 
                {
                    error(curBlock.startLine.file, curBlock.startLine.lineNum, "Unclosed block {" ~ curBlock.name ~ "}");
                }
                // Make sure the section exists
                if (curSection !is null) 
                {
                    chapter.sections ~= curSection;
                }
                int hashMarkCounter = 0;
                while (line.startsWith("#")) 
                {
                    hashMarkCounter++;
                    line.popFront();
                }
                if (hashMarkCounter > 6) 
                {
                    error(filename, lineNum, "Too many hashmarks");
                }
                curSection = new Section();
                curSection.title = strip(line);
                curSection.level = hashMarkCounter - 1;
                curSection.commands = chapter.commands ~ curSection.commands;
                increaseSectionNum(curSection.level);
                curSection.num = sectionNum;
            
                curBlock = new Block();
                curBlock.isCodeblock = false;
            }

            // Parse the beginning of a code block
            else if (matchAll(line, regex("^```.+"))) 
            {
                if (curSection is null) 
                {
                    error(chapter.file, lineNum, "You must define a section with # before writing a code block");
                    continue;
                }
            
                if (curBlock !is null) curSection.blocks ~= curBlock;
                
                curBlock = new Block();
                curBlock.startLine = lineObj;
                curBlock.isCodeblock = true;
                curBlock.name = curSection.title;
            
                // Parse Modifiers
                auto checkForModifiers = ctRegex!(`(?P<namea>\S.*)[ \t]-{3}[ \t](?P<modifiers>.+)|(?P<nameb>\S.*?)[ \t]*?(-{1,}$|$)`);
                auto splitOnSpace = ctRegex!(r"(\s+)");
                auto modMatch = matchFirst(curBlock.name, checkForModifiers);
                
                // matchFirst returns unmatched groups as empty strings
                
                if (modMatch["namea"] != "") 
                {
                    curBlock.name = modMatch["namea"];
                } 
                else if (modMatch["nameb"] != "")
                {
                    curBlock.name = modMatch["nameb"];
                    // Check for old syntax.
                    if (curBlock.name.endsWith("+=")) 
                    {
                        curBlock.modifiers ~= Modifier.additive;
                        curBlock.name = strip(curBlock.name[0..$-2]);
                    } 
                    else if (curBlock.name.endsWith(":=")) 
                    {
                        curBlock.modifiers ~= Modifier.redef;
                        curBlock.name = strip(curBlock.name[0..$-2]);
                    }
                } 
                else 
                {
                    error(filename, lineNum, "Something went wrong with: " ~ curBlock.name);
                }
                
                if (modMatch["modifiers"]) 
                {
                    foreach (m; splitter(modMatch["modifiers"], splitOnSpace)) 
                    {
                        switch(m) 
                        {
                            case "+=":
                                curBlock.modifiers ~= Modifier.additive;
                                break;
                            case ":=":
                                curBlock.modifiers ~= Modifier.redef;
                                break;
                            case "noWeave":
                                curBlock.modifiers ~= Modifier.noWeave;
                                break;
                            case "noTangle":
                                curBlock.modifiers ~= Modifier.noTangle;
                                break;
                            default:
                                error(filename, lineNum, "Invalid modifier: " ~ m);
                                break;
                        }
                    }
                }

            
                if (blocks.canFind(curBlock.name)) 
                {
                    if (!curBlock.modifiers.canFind(Modifier.redef) && !curBlock.modifiers.canFind(Modifier.additive)) 
                    {
                        error(filename, lineNum, "Redefinition of {" ~ curBlock.name ~ "}, use ':=' to redefine");
                    }
                } 
                else 
                {
                    blocks ~= curBlock.name;
                }
            
                foreach (cmd; curSection.commands) 
                {
                    if (cmd.name == "@code_type") 
                    {
                        curBlock.codeType = cmd.args;
                    } 
                    else if (cmd.name == "@comment_type") 
                    {
                        if (curBlock.name.endsWith(" noComment")) 
                        {
                            curBlock.name = curBlock.name[0..$-10];
                            curBlock.commentString = "";
                        } 
                        else 
                        {
                            curBlock.commentString = cmd.args;
                        }
                    }
                }
            
                inCodeblock = true;
            }

            else if (curBlock !is null) 
            {
                if (line.split().length > 1) 
                {
                    if (commands.canFind(line.split()[0])) continue;
                }
                // Add the line to the list of lines
                curBlock.lines ~= new Line(line, filename, lineNum);

            }
        } 
        else if (startsWith(line, "```")) 
        {
            // Begin a new prose block
            if (curBlock !is null) curSection.blocks ~= curBlock;
            curBlock = new Block();
            curBlock.startLine = lineObj;
            curBlock.isCodeblock = false;
            inCodeblock = false;

        } 
        else if (curBlock !is null) 
        {
            // Add the line to the list of lines
            curBlock.lines ~= new Line(line, filename, lineNum);

        }

    }
    // Close the last section
    if (curBlock !is null) 
    {
        if (!curBlock.isCodeblock) 
        {
            curSection.blocks ~= curBlock;
        } 
        else 
        {
            writeln(filename, ":", lines.length - 1, ":error: {", curBlock.name, "} is never closed");
        }
    }
    if (curSection !is null) 
    {
        chapter.sections ~= curSection;
    }


    return chapter;
}



