@code_type d .d
@comment_type // %s
@compiler make debug -C ..
@error_format .*/%f\(%l,%s\):%s: %m

@title Literate

# Introduction

This is an implementation of a literate programming system in D.
The goal is to be able to create books that one can read on a website;
with chapters, subchapters, and sections, and additionally to be able
to compile the code from the book into a working program.

Literate programming aims to make the source code of a program
understandable. The program can be structured in any way the
programmer likes, and the code should be explained.

The source code for a literate program will somewhat resemble
CWEB, but differ in many key ways which simplifies the source code
and make it easier to read. Literate will use @ signs for commands
and markdown to style the prose.

# Directory Structure

A literate program may be just a single file, but it should also be
possible to make a book out of it, with chapters and possibly multiple
programs in a single book. If the literate command line tool is run on
a single file, it should compile that file, if it is run on a directory,
it should search for the `Summary.md` file in the directory and create a
book.

What should the directory structure of a Literate book look like?
I try to mimic the [Gitbook](https://github.com/GitbookIO/gitbook) software
here. There will be a `Summary.md` file which links to each of the
different chapters in the book. An example `Summary.md` file might look
like this:

```lit
    @title Title of the book

    [Chapter 1](chapter1/intro.md)
        [Subchapter 1](chapter1/example1.md)
        [Subchapter 2](chapter1/example2.md)
    [Chapter 2](section2/intro.md)
        [Subchapter 1](chapter2/example1.md)
```

Subchapters are denoted by tabs, and each chapter is linked to the correct
`.md` file using Markdown link syntax.

# The Parser

As a first step, I'll make a parser for single chapters only, and leave having
multiple chapters and books for later.

The parser will have 2 main parts to it: the one which represents the various structures
of a literate program, and the parse function.

## src/parser.d
```d
@{Parser imports}
@{Classes}
@{Parse functions}
```

I'll quickly list the imports here.

## Parser imports
```d
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
```

## Classes

Now we have to define the classes used to represent a literate program. There
are 7 such classes:

```d
@{Line class}
@{Command class}
@{Block class}
@{Section class}
@{Chapter class}
@{Program class}
@{Change class}
```

### Program class

What is a literate program at the highest level? A program has multiple chapters,
it has a title, and it has various commands associated with it (although some of these
commands may be overwritten by chapters or even sections). It also has the file it
originally came from.

```d
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
```

### Chapter class

A chapter is very similar to a program. It has a title, commands, sections, and also
an original file. In the case of a single file program (which is what we are focusing
on for the moment) the Program's file and the Chapter's file will be the same. A chapter
also has a minor number and a major number;

```d
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
```

### Section class

A section has a title, commands, a number, and a series of blocks, which can either be
blocks of code, or blocks of prose.

We can also attribute a level to sections which allows us to organize our
sections hierarchically. Six levels are supported at the moment; in the final 
document these are translated to HTML tags `&lt;h1&gt;` to `&lt;h6&gt;`.

Accordingly, the section number is an array of six numbers in fact. Two
support functions are needed to handle the number array seamlessly:

* First we need a function to convert this array to a string - the `numToString`
  class method does this for us. The only trick we need to consider here is not
  to include trailing zeros to our result string.

* Second, we need a function to increase the numbering according to the section's
  level. The `increaseSectionNum` function called during chapter parsing (i.e.
  in the `parseChapter` call) is responsible for this (for more details see the
  description of `parseChapter`).

```d
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
```

### Block class

A block is more interesting. It can either be a block of code, or a block of prose, so
it has a boolean which represents what type it is. It also stores a start line. If it
is a code block, it also has a name. Finally, it stores an array of lines, and has a function
called `text()` which just returns the string of the text it contains. A block also contains
a `codeType` and a `commentString`.

```d
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
```

### Command class

A command is quite simple. It has a name, and any arguments that are passed.

```d
class Command 
{
    public string name;
    public string args;
    public int lineNum;
    public string filename;
}
```

### Line class

A line is the lowest level. It stores the line number, the file the line is from, and the
text for the line itself.


```d
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
```

### Change class

The change class helps when parsing a change statement. It stores the file that is being changed,
what the text to search for is and what the text to replace it with is. These two things are arrays
because you can make multiple changes (search and replaces) to one file. In order to
keep track of the current change, an index is also stored.

```d
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
```

That's it for the classes. These 7 classes can be used to represent an entire literate program.
Now let's get to the actual parse function to turn a text file into a program.

## Parse functions

Here we have two functions: `parseProgram` and `parseChapter`.

```d
@{parseProgram function}
@{parseChapter function}
```

### parseProgram function

This function takes a literate book source and parses each chapter and returns the final program.

Here is an example book:

    @title Title of the book

    [Chapter 1](chapter1/intro.lit)
        [Subchapter 1](chapter1/example1.lit)
        [Subchapter 2](chapter1/example2.lit)
    [Chapter 2](section2/intro.lit)
        [Subchapter 1](chapter2/example1.lit)

```d
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
```

### parseChapter function

The `parseChapter` function is the more complex one. It parses the source of a chapter.
Before doing any parsing, we resolve the `@include` statements by replacing them with
the contents of the file that was included. Then we loop through each line in the source
and parse it, provided that it is not a comment (starting with `//`);

```d
Chapter parseChapter(Chapter chapter, string src) 
{
    @{Initialize some variables}
    @{Increase section number}

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
        
        @{Parse the line}
    }
    @{Close the last section}

    return chapter;
}
```

### The Parse Function Setup

For the initial variables, it would be nice to move the value for `chapter.file` into a variable
called `filename`. Additionally, I'm going to need an array of all the possible commands that
are recognized.

#### Initialize some variables
```d
string filename = chapter.file;
string[] commands = ["@code_type", "@comment_type", "@compiler", "@error_format",
                     "@add_css", "@overwrite_css", "@colorscheme", "@include"];
```

I also need to keep track of the current section that is being parsed, and the current block that
is being parsed, because the parser is going through the file one line at a time. I'll also define
the current change being parsed.

#### Initialize some variables +=
```d
Section curSection;
int[6] sectionNum = [0, 0, 0, 0, 0, 0];
Block curBlock;
Change curChange;
```

Finally, I need 3 flags to keep track of if it is currently parsing a codeblock, a search block,
or a replace block.

#### Initialize some variables +=
```d
bool inCodeblock = false;
bool inSearchBlock = false;
bool inReplaceBlock = false;
```

### Parse the line

When parsing a line, we are either inside a code block, or inside a prose block, or we are transitioning
from one to the other. So we'll have an if statement to separate the two.

```d
if (!inCodeblock) 
{
    // This might be a change block
    @{Parse change block}
    @{Parse a command}
    @{Parse a title command}
    @{Parse a section definition}
    @{Parse the beginning of a code block}
    else if (curBlock !is null) 
    {
        if (line.split().length > 1) 
        {
            if (commands.canFind(line.split()[0])) continue;
        }
        @{Add the line to the list of lines}
    }
} 
else if (startsWith(line, "```")) 
{
    @{Begin a new prose block}
} 
else if (curBlock !is null) 
{
    @{Add the line to the list of lines}
}
```

Parsing a command and the title command are both fairly simple, so let's look at them first.

To parse a command we first make sure that there is the command name, and any arguments.
Then we check if the command is part of the list of commands we have. If it is, we
create a new command object, fill in the name and arguments, and add it to the chapter object.

We also do something special if it is a `@include` command. For these ones, we take the file
read it, and parse it as a chapter (using the `parseChapter` function). Then we add the
included chapter's sections to the current chapter's sections. In this case, we don't add
the `@include` command to the list of chapter commands.

#### Parse a command
```d
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
```

Parsing an `@title` command is even simpler.

#### Parse a title command
```d
if (startsWith(line, "@title")) 
{
    chapter.title = strip(line[6..$]);
}
```

### Parse a section definition

When a new section is created (using `#` .. `######`), we should add the current section to the list
of sections for the chapter, and then we should create a new section, which becomes the
current section.

```d
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
```

#### Increase section number

Section number increase - since we support six levels of sections to have a
hierarchical structure even inside a chapter - depends on the section's level.
When we increase the number of a certain level, all lower levels need to be
zeroed out. The `increaseSectionNum` function does this job for us.

```d
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
```

### Parse the beginning of a code block

Codeblocks always begin with three backticks, so we can use a proper regex to represent this.
Once a new codeblock starts, the old one must be appended to the current section's list of
blocks, and the current codeblock must be reset.

```d
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

    @{Parse Modifiers}

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
```

### Check for and extract modifiers.

Modifier format for a code block: `--- Block Name --- noWeave +=`.
The `checkForModifiers` ugliness is due to lack of `(?|...)` and friends.

First half matches for expressions *with* modifiers:

1. `(?P<namea>\S.*)` : Keep taking from the first non-whitespace character ...
2. `[ \t]-{3}[ \t]` : Until it matches ` --- `
3. `(?P<modifiers>.+)` : Matches everything after the separator.

Second half matches for no modifiers: Ether `Block name` and with a floating separator `Block Name ---`.

1. `|(?P<nameb>\S.*?)` : Same thing as #1 but stores it in `nameb`
2. `[ \t]*?` : Checks for any amount of whitespace (Including none.)
3. `(-{1,}$` : Checks for any floating `-` and verifies that nothing else is there untill end of line.
4. `|$))` : Or just checks that there is nothing but the end of the line after the whitespace.

Returns ether `namea` and `modifiers` or just `nameb`.

#### Parse Modifiers
```d
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
```

### Parse the End of a Codeblock

Codeblocks end with just a three backticks. When a codeblock ends, we do the same as when it begins,
except the new block we create is a block of prose as opposed to code.

#### Begin a new prose block
```d
if (curBlock !is null) curSection.blocks ~= curBlock;
curBlock = new Block();
curBlock.startLine = lineObj;
curBlock.isCodeblock = false;
inCodeblock = false;
```

### Add the current line

Finally, if the current line is nothing interesting, we just add it to the current block's
list of lines.

#### Add the line to the list of lines
```d
curBlock.lines ~= new Line(line, filename, lineNum);
```

Now we're done parsing the line.

### Close the last section

When the end of the file is reached, the last section has not been closed and added to the
chapter yet, so we should do that. Additionally, if the last block is a prose block, it should
be closed and added to the section first. If the last block is a code block, it should have been
closed with three backticks. If it was not, we throw an error.

```d
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
```

### Parse change block

Parsing a change block is somewhat complex. Change blocks look like this:

    @change file.lit

    Some comments here...

    @replace
    replace this text
    @with
    with this text
    @end

    More comments ...

    @replace
    ...
    @with
    ...
    @end

    ...

    @change_end

You can make multiple changes on one file. We've got two nice flags for keeping track of
which kind of block we are in: replaceText or searchText.

```d
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
```

# Weaver

Here is an overview of the weave functionality. This file turns a literate source
file into one or more Markdown files. The Markdown files created contain proper
cross references, references to code blocks and can be converted into HTML, PDF
or any other output formats by e.g. `pandoc`.

## src/weaver.d
```d
@{Weaver imports}

void weave(Program p) 
{
    @{Parse use locations}
    @{Run weaveChapter}
    if (isBook && !noOutput) 
    {
@{Create the table of contents}
    }
}

@{WeaveChapter}
@{LinkLocations function}
```

## Parsing Codeblocks

Now we parse the codeblocks across all chapters in the program. We
have four arrays:

* defLocations: stores the section in which a codeblock is defined.
* redefLocations: stores the sections in which a codeblock is redefined.
* addLocations: stores the sections in which a codeblock is added to.
* useLocations: stores the sections in which a codeblock is used;

### Parse use locations
```d
string[string] defLocations;
string[][string] redefLocations;
string[][string] addLocations;
string[][string] useLocations;

foreach (chapter; p.chapters) 
{
    foreach (s; chapter.sections) 
    {
        foreach (block; s.blocks) 
        {
            if (block.isCodeblock) 
            {
                if (block.modifiers.canFind(Modifier.noWeave)) 
                {
                    defLocations[block.name] = "noWeave";
                    continue;
                }

                @{Check if it's a root block}

                if (block.modifiers.canFind(Modifier.additive)) 
                {
                    if (block.name !in addLocations || !addLocations[block.name].canFind(s.numToString()))
                    {
                        addLocations[block.name] ~= chapter.num() ~ ":" ~ s.numToString();
                    }
                } 
                else if (block.modifiers.canFind(Modifier.redef)) 
                {
                    if (block.name !in redefLocations || !redefLocations[block.name].canFind(s.numToString()))
                    {
                        redefLocations[block.name] ~= chapter.num() ~ ":" ~ s.numToString();
                    }
                } 
                else 
                {
                    defLocations[block.name] = chapter.num() ~ ":" ~ s.numToString();
                }

                foreach (lineObj; block.lines) 
                {
                    string line = strip(lineObj.text);
                    if (line.startsWith("@{") && line.endsWith("}")) 
                    {
                        useLocations[line[2..$ - 1]] ~= chapter.num() ~ ":" ~ s.numToString();
                    }
                }
            }
        }
    }
}
```

Here we simply loop through all the chapters in the program and get the Markdown for them.
If `noOutput` is false, we generate Markdown files in the `outDir`.

## Run weaveChapter
```d
foreach (c; p.chapters) 
{
    string output = weaveChapter(c, p, defLocations, redefLocations,
                                 addLocations, useLocations);
    if (!noOutput) 
    {
        string dir = outDir;
        if (isBook) 
        {
            dir = outDir ~ "/_book";
            if (!dir.exists()) mkdir(dir);
        }
        File f = File(dir ~ "/" ~ stripExtension(baseName(c.file)) ~ ".html", "w");
        f.write(output);
        f.close();
    }
}
```

## Table of contents

If the program being compiled is a book, we should also write a table of contents file.
The question is whether we need this feature when we drop the html output
completely... (Robert)

### Create the table of contents
```d
string dir = outDir ~ "/_book";
File f = File(dir ~ "/" ~ p.title ~ "_contents.html", "w");

f.writeln(
q"DELIMITER
<!DOCTYPE html>
<html>
<head>
</head>
<body>
<div class="container">
DELIMITER"
);

f.writeln("<h1>" ~ p.title ~ "</h1>");

string html;
string md = p.text;
if (useMdCompiler) 
{
    auto pipes = pipeShell(mdCompilerCmd, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdin.write(md);
    pipes.stdin.flush();
    pipes.stdin.close();
    auto status = wait(pipes.pid);
    string mdCompilerOutput;
    foreach (line; pipes.stdout.byLine) mdCompilerOutput ~= line.idup;
    if (status != 0) 
    {
        warn(p.file, 1, "Custom markdown compilation failed: " ~ mdCompilerOutput ~ " -- Falling back to built-in markdown compiler");
        html = filterMarkdown(md, MarkdownFlags.backtickCodeBlocks);
        useMdCompiler = false;
    } 
    else 
    {
        html = mdCompilerOutput;
    }
} 
else 
{
    html = filterMarkdown(md, MarkdownFlags.backtickCodeBlocks);
}

f.writeln(html);

f.writeln("<ul id=\"contents\">");
foreach (c; p.chapters) 
{
    f.writeln("<li>" ~ c.num() ~ ". <a href=\"" ~ stripExtension(baseName(c.file)) ~ ".html\">" ~ c.title ~ "</a></li>");
}

f.writeln("
</ul>
</div>
</body>
");

f.close();

```

## Root block check

We check if the block is a root code block. We check this using
a regex that basically checks if it the name has an extension. Additionally,
users can put the block name in quotes to force it to be a root block.

If the block name is in quotes, we have to make sure to remove those once
we're done.

### Check if it's a root block
```d
auto fileMatch = matchAll(block.name, regex(".*\\.\\w+"));
auto quoteMatch = matchAll(block.name, regex("^\".*\"$"));
if (fileMatch || quoteMatch) 
{
    block.isRootBlock = true;
    if (quoteMatch) block.name = block.name[1..$-1];  
}
```

## WeaveChapter

This function weaves a single chapter.

```d
string weaveChapter(Chapter c, Program p, string[string] defLocations,
                    string[][string] redefLocations, string[][string] addLocations,
                    string[][string] useLocations) 
{
@{css}

    string output;

    string prettify;
    string[string] extensions;

@{Write the head of the HTML}
@{Write the body}

	if (use_katex) 
	{
@{Write the katex source}
    }

    if (isBook) {
        output ~= "<br>";
        int index = cast(int) p.chapters.countUntil(c);
        if (index - 1 >= 0) 
        {
            Chapter lastChapter = p.chapters[p.chapters.countUntil(c)-1];
            output ~= "<a style=\"float:left;\" class=\"chapter-nav\" href=\"" ~ stripExtension(baseName(lastChapter.file)) ~ ".html\">Previous Chapter</a>";
        }
        if (index + 1 < p.chapters.length) 
        {
            Chapter nextChapter = p.chapters[p.chapters.countUntil(c)+1];
            output ~= "<a style=\"float:right;\" class=\"chapter-nav\" href=\"" ~ stripExtension(baseName(nextChapter.file)) ~ ".html\">Next Chapter</a>";
        }
    }

    output ~= "</body>\n";
    return output;
}
```

## Write the head of the HTML

This writes out the start of the document. Mainly the scripts (prettify.js) 
and the css (prettiy css, default css, and colorscheme css). It also adds
the title of the document.

```d 
string prettifyExtension;
foreach (cmd; p.commands) 
{
    if (cmd.name == "@overwrite_css") 
    {
        defaultCSS = readall(File(cmd.args));
    } 
    else if (cmd.name == "@add_css") 
    {
        defaultCSS ~= readall(File(cmd.args));
    } 
    else if (cmd.name == "@colorscheme") 
    {
        colorschemeCSS = readall(File(cmd.args));
    }

    if (cmd.name == "@code_type") 
    {
        if (cmd.args.length > 1) 
        {
            string ext = cmd.args.split()[1][1..$];
            if (ext in extensions) 
            {
                prettifyExtension = "<script>\n" ~ extensions[ext] ~ "</script>\n";
            }
        }
    }
}
foreach (cmd; c.commands) 
{
    if (cmd.name == "@overwrite_css") 
    {
        defaultCSS = readall(File(cmd.args));
    } 
    else if (cmd.name == "@add_css") 
    {
        defaultCSS ~= readall(File(cmd.args));
    } 
    else if (cmd.name == "@colorscheme") 
    {
        colorschemeCSS = readall(File(cmd.args));
    }

    if (cmd.name == "@code_type") 
    {
        if (cmd.args.length > 1) 
        {
            string ext = cmd.args.split()[1][1..$];
            if (ext in extensions) 
            {
                prettifyExtension = "<script>\n" ~ extensions[ext] ~ "</script>\n";
            }
        }
    }
}

string css = colorschemeCSS ~ defaultCSS;
string bootstrapcss = q"DELIMITER
<!-- Bootstrap CSS -->
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/css/bootstrap.min.css" integrity="sha384-MCw98/SFnGE8fJT3GXwEOngsV7Zt27NXFoaoApmYm81iuXoPkFOJwJ8ERdknLPMO" crossorigin="anonymous">
 <link rel="stylesheet" href="https://cdn.rawgit.com/afeld/bootstrap-toc/v1.0.0/dist/bootstrap-toc.min.css">
DELIMITER";
string scripts = "<script>\n" ~ prettify ~ "</script>\n";
scripts ~= prettifyExtension;

string bootstrapscript = q"DELIMITER
<script src="https://code.jquery.com/jquery-3.3.1.slim.min.js" integrity="sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo" crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.3/umd/popper.min.js" integrity="sha384-ZMP7rVo3mIykV+2+9J3UJ46jBk0WLaUAdn689aCwoqbBJiSnjAK/l8WvCWPIPm49" crossorigin="anonymous"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/js/bootstrap.min.js" integrity="sha384-ChfqqxuZUCnJSK3+MXmPNIyE6ZbWh2IMqE241rYiqJxyMiZ6OW/JmZQ5stwEULTy" crossorigin="anonymous"></script>
<script src="https://cdn.rawgit.com/afeld/bootstrap-toc/v1.0.0/dist/bootstrap-toc.min.js"></script>
DELIMITER";

scripts ~= bootstrapscript;

bool use_katex = false;

output ~= "<!DOCTYPE html>\n" ~
             "<html>\n" ~
             "<head>\n" ~
             "<meta charset=\"utf-8\">\n" ~
             "<title>" ~ c.title ~ "</title>\n" ~
             bootstrapcss ~
             scripts ~
             "<style>\n" ~
             css ~
             "</style>\n" ~
             "</head>\n";
```

## Parse the Chapter

Now we write the body -- this is the meat of the weaver. First we write
a couple things at the beginning: making sure the `prettyprint` function is
called when the page loads, and writing out the title as an `h1`.

Then we loop through each section in the chapter. At the beginning of each section,
we write the title, and an empty `a` link so that the section title can be linked to.
We also have to determine if the section title should be a `noheading` class. If the
section title is empty, then the class should be `noheading` which means that the prose
will be moved up a bit towards it -- otherwise it looks like there is too much empty space
between the title and the prose.

## Write the body
```d
output ~= q"DELIMITER
<body onload="prettyPrint()"  data-spy="scroll" data-target="#toc">
<div class="row">
<div class="col-sm-3">
<nav id="toc" data-spy="affix" data-toggle="toc"></nav>
</div>
<div class="col-sm-9">
DELIMITER";
output ~= "<p id=\"title\">" ~ c.title ~ "</p>";

foreach (s; c.sections) 
{
	string noheading = s.title == "" ? " class=\"noheading\"" : "";
    output ~= "<a name=\"" ~ c.num() ~ ":" ~ s.numToString() ~ "\"><div class=\"section\"><h" ~ to!string(s.level + 1) ~
              noheading ~ ">" ~ s.numToString() ~ ". " ~ s.title ~ "</h" ~ to!string(s.level + 1) ~ "></a>\n";
    
    foreach (block; s.blocks) 
    {
        if (!block.modifiers.canFind(Modifier.noWeave)) 
        {
            if (!block.isCodeblock) 
            {
                @{Weave a prose block}
            } 
            else 
            {
                @{Weave a code block}
            }
        }
    }
	output ~= "</div>\n";
}

output ~= "</div>\n"; // matches <div class="col-sm-9">
output ~= "</div>\n"; // matches <div class="row">
```

## Weave a prose block

Weaving a prose block is not very complicated. 

```d
string html;
string md;

foreach (lineObj; block.lines) 
{
    auto l = lineObj.text;
    if (l.matchAll(regex(r"@\{.*?\}"))) 
    {
        auto matches = l.matchAll(regex(r"@\{(.*?)\}"));
        foreach (m; matches) 
        {
            auto def = "";
            auto defLocation = "";
            auto str = strip(m[1]);
            if (str !in defLocations) 
            {
                error(lineObj.file, lineObj.lineNum, "{" ~ str ~ "} is never defined");
            } 
            else if (defLocations[str] != "noWeave") 
            {
                def = defLocations[str];
                defLocation = def;
                auto index = def.indexOf(":");
                string chapter = def[0..index];
                auto htmlFile = getChapterHtmlFile(p.chapters, chapter);
                if (chapter == c.num()) defLocation = def[index + 1..$];       
                l = l.replaceAll(regex(r"@\{" ~ str ~ r"\}"), "`{" ~ str ~ ",`[`" ~ defLocation ~ "`](" ~ htmlFile ~ "#" ~ def ~ ")`}`");
            }
        }
    }
    md ~= l ~ "\n";
}

if (md.matchAll(regex(r"(?<!\\)[\$](?<!\\)[\$](.*?)(?<!\\)[\$](?<!\\)[\$]")) || md.matchAll(regex(r"(?<!\\)[\$](.*?)(?<!\\)[\$]"))) 
{
    use_katex = true;
}

md = md.replaceAll(regex(r"(?<!\\)[\$](?<!\\)[\$](.*?)(?<!\\)[\$](?<!\\)[\$]", "s"), "<div class=\"math\">$1</div>");
md = md.replaceAll(regex(r"(?<!\\)[\$](.*?)(?<!\\)[\$]", "s"), "<span class=\"math\">$1</span>");
md = md.replaceAll(regex(r"\\\$"), "$$");


if (useMdCompiler) 
{
    auto pipes = pipeShell(mdCompilerCmd, Redirect.stdin | Redirect.stdout | Redirect.stderrToStdout);
    pipes.stdin.write(md);
    pipes.stdin.flush();
    pipes.stdin.close();
    auto status = wait(pipes.pid);
    string mdCompilerOutput;
    foreach (line; pipes.stdout.byLine) mdCompilerOutput ~= line.idup;
    if (status != 0) 
    {
        warn(c.file, 1, "Custom markdown compilation failed: " ~ mdCompilerOutput ~ " -- Falling back to built-in markdown compiler");
        html = filterMarkdown(md, MarkdownFlags.disableUnderscoreEmphasis);
        useMdCompiler = false;
    } 
    else 
    {
        html = mdCompilerOutput;
    }
} 
else 
{
    html = filterMarkdown(md, MarkdownFlags.disableUnderscoreEmphasis);
}

```

Here we use the same regex to actually perform the substitution. Double dollars mean a block math
which means we have to use a div. For inline math (single dollars) we use a span. After that substitution
we replace all backslash dollars to real dollar signs.

Finally we add this html to the output and add a newline for good measure.

### Weave a prose block +=
```d
output ~= md ~ "\n";
```

## Weave a code block

```d
output ~= "<div class=\"codeblock\">\n";

@{Write the title out}
@{Write the actual code}
@{Write the 'added to' links}
@{Write the 'redefined in' links}
@{Write the 'used in' links}

output ~= "</div>\n";
```

### The codeblock title

Here we create the title for the codeblock. For the title, we have to link
to the definition (which is usually the current block, but sometimes not
because of `+=`). We also need to make the title bold (`&lt;strong&gt;`) if it
is a root code block.

#### Write the title out
```d
@{Find the definition location}
@{Make the title bold if necessary}

output ~= "<span class=\"codeblock_name\">{" ~ name ~
          " <a href=\"" ~ htmlFile ~ "#" ~ def ~ "\">" ~ defLocation ~ "</a>}" ~ extra ~ "</span>\n";
```

To find the definition location we use the handy `defLocation` array that we made
earlier. The reason we have both the variables `def` and `defLocation` is because
the definition location might be in another chapter, in which case it should be
displayed as `chapterNum:sectionNum` but if it's in the current file, the `chapterNum`
can be removed. `def` gives us the real definition location, and `defLocation` is the
one that will be used -- it strips out the `chapterNum` if necessary.

#### Find the definition location
```d
string chapterNum;
string def;
string defLocation;
string htmlFile = "";
if (block.name !in defLocations) 
{
    error(block.startLine.file, block.startLine.lineNum, "{" ~ block.name ~ "} is never defined");
} 
else 
{
    def = defLocations[block.name];
    defLocation = def;
    auto index = def.indexOf(":");
    string chapter = def[0..index];
    htmlFile = getChapterHtmlFile(p.chapters, chapter);
    if (chapter == c.num()) 
    {
        defLocation = def[index + 1..$];
    }
}
```

We also add the `+=` or `:=` if necessary. This needs to be the `extra` because
it goes outside the `{}` and is not really part of the name anymore.

#### Find the definition location +=
```d
string extra = "";
if (block.modifiers.canFind(Modifier.additive)) 
{
    extra = " +=";
} 
else if (block.modifiers.canFind(Modifier.redef)) 
{
    extra = " :=";
}
```

We simple put the title in in a strong tag if it is a root codeblock to make it bold.

#### Make the title bold if necessary
```d
string name;
if (block.isRootBlock) name = "<strong>" ~ block.name ~ "</strong>";
else name = block.name;

```

### The actual code

At the beginning, we open the pre tag. If a codetype is defined, we tell the prettyprinter
to use that, otherwise, the pretty printer will try to figure out how to syntax highlight
on its own -- and it's pretty good at that.

#### Write the actual code
```d
if (block.codeType.split().length > 1) 
{
    if (block.codeType.split()[1].indexOf(".") == -1) 
    {
        warn(block.startLine.file, 1, "@code_type extension must begin with a '.', for example: `@code_type c .c`");
    } 
    else 
    {
        output ~= "<pre class=\"prettyprint lang-" ~ block.codeType.split()[1][1..$] ~ "\">\n";
    }
} 
else 
{
    output ~= "<pre class=\"prettyprint\">\n";
}

foreach (lineObj; block.lines) 
{
    @{Write the line}
}
output ~= "</pre>\n";
```

Now we loop through each line. The only complicated thing here is if the line is
a codeblock use. Then we have to link to the correct definition location.

Also we escape all ampersands and greater than and less than signs before writing them.

#### Write the line
```d
string line = lineObj.text;
string strippedLine = strip(line);
if (strippedLine.startsWith("@{") && strippedLine.endsWith("}")) 
{
    @{Link a used codeblock}
} 
else 
{
    output ~= line.replace("&", "&amp;").replace(">", "&gt;").replace("<", "&lt;") ~ "\n";
}
```

For linking the used codeblock, it's pretty much the same deal as before. We
reuse the `def` and `defLocation` variables. We also write the final html as
a span with the `nocode` class, that way it won't be syntax highlighted by the
pretty printer.

#### Link a used codeblock
```d
def = "";
defLocation = "";
if (strip(strippedLine[2..$ - 1]) !in defLocations) 
{
    error(lineObj.file, lineObj.lineNum, "{" ~ strip(strippedLine[2..$ - 1]) ~ "} is never defined");
} 
else if (defLocations[strip(strippedLine[2..$ - 1])] != "noWeave") 
{
    def = defLocations[strippedLine[2..$ - 1]];
    defLocation = def;
    auto index = def.indexOf(":");
    string chapter = def[0..index];
    htmlFile = getChapterHtmlFile(p.chapters, chapter);
    if (chapter == c.num()) 
    {
        defLocation = def[index + 1..$];
    }
    def = ", <a href=\"" ~ htmlFile ~ "#" ~ def ~ "\">" ~ defLocation ~ "</a>";
}
output ~= "<span class=\"nocode pln\">" ~ leadingWS(line) ~ "{" ~ strippedLine[2..$ - 1] ~ def ~ "}</span>\n";
```

### Add links to other sections

Writing the links is pretty similar to figuring out where a codeblock
was defined because we have access to the `sectionLocations` array (which is
`addLocations`, `useLocations`, or `redefLocations`). Then we just
have a few if statements to figure out the grammar -- where to put the `and`
and whether to have plurals and whatnot.

#### LinkLocations function
```d
T[] noDupes(T)(in T[] s) 
{
    import std.algorithm: canFind;
    T[] result;
    foreach (T c; s)
    {
        if (!result.canFind(c)) result ~= c;
    }
    return result;
}

string linkLocations(string text, string[][string] sectionLocations, Program p, Chapter c, Section s, parser.Block block) 
{
    if (block.name in sectionLocations) 
    {
        string[] locations = dup(sectionLocations[block.name]).noDupes;

        if (locations.canFind(c.num() ~ ":" ~ s.numToString())) 
        {
            locations = remove(locations, locations.countUntil(c.num() ~ ":" ~ s.numToString()));
        }

        if (locations.length > 0) 
        {
            string seealso = "<p class=\"seealso\">" ~ text;

            if (locations.length > 1) seealso ~= "s ";
            else seealso ~= " ";
            
            foreach (i; 0 .. locations.length) 
            {
                string loc = locations[i];
                string locName = loc;
                auto index = loc.indexOf(":");
                string chapter = loc[0..index];
                string htmlFile = getChapterHtmlFile(p.chapters, chapter);
                if (chapter == c.num()) locName = loc[index + 1..$];
                loc = "<a href=\"" ~ htmlFile ~ "#" ~ loc ~ "\">" ~ locName ~ "</a>";
                if (i == 0) seealso ~= loc;
                else if (i == locations.length - 1) seealso ~= " and " ~ loc;
                else seealso ~= ", " ~ loc;
                
            }
            seealso ~= "</p>";
            return seealso;
        }
    }
    return "";
}
```

### See also links

Writing the 'added to' links is pretty similar to figuring out where a codeblock
was defined because we have access to the `addLocations` array. Then we just
have a few if statements to figure out the grammar -- where to put the `and`
and whether to have plurals and whatnot.

#### Write the 'added to' links
```d
output ~= linkLocations("Added to in section", addLocations, p, c, s, block) ~ "\n";
```

### Also used in links

This is pretty much the same as the 'added to' links except we use the
`useLocations` array.

#### Write the 'used in' links
```d
output ~= linkLocations("Used in section", useLocations, p, c, s, block) ~ "\n";
```

### Redefined in links

#### Write the 'redefined in' links
```d
output ~= linkLocations("Redefined in section", redefLocations, p, c, s, block) ~ "\n";
```

## Katex source

This is the source code for katex which should only be used if math is used in the literate
file. We include a script which uses the cdn first because that will use better fonts, however
it needs the user to be connected to the internet. In the case that the user is offline, we include
the entire source for katex, but it will use worse fonts (still better than nothing though).

### Write the katex source
```d
output ~= "<link rel=\"stylesheet\" href=\"http://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.3.0/katex.min.css\">\n" ~
"<script src=\"http://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.3.0/katex.min.js\"></script>\n";
```

Then we loop over all the math divs and spans and render the katex.

### Write the katex source +=
```d
output ~= q"DELIMITER
<script>
var mathDivs = document.getElementsByClassName("math")
for (var i = 0; i < mathDivs.length; i++) {
    var el = mathDivs[i];
    var texTxt = el.textContent;
    try {
        var displayMode = false;
        if (el.tagName == 'DIV') {
            displayMode = true;
        }
        katex.render(texTxt, el, {displayMode: displayMode});
    }
    catch(err) {
        el.innerHTML = "<span class='err'>"+err+"</span>";
    }
}
</script>
DELIMITER";
```

## css
```d
string colorschemeCSS = q"DELIMITER
.pln{color:#1b181b}
.str{color:#918b3b}
.kwd{color:#7b59c0}
.com{color:#9e8f9e}
.typ{color:#516aec}
.lit{color:#a65926}
.clo,
.opn,
.pun{color:#1b181b}
.tag{color:#ca402b}
.atn{color:#a65926}
.atv{color:#159393}
.dec{color:#a65926}
.var{color:#ca402b}
.fun{color:#516aec}
pre.prettyprint
{
	background:#f7f3f7;
	color:#ab9bab;
	font-family:Menlo,Consolas,"Bitstream Vera Sans Mono","DejaVu Sans Mono",Monaco,monospace;
	font-size:12px;
	line-height:1.5;
	border:1px solid #d8cad8;
	padding:10px
}
ol.linenums{margin-top:0;margin-bottom:0}
DELIMITER";

string defaultCSS = q"DELIMITER
html {
 	font-family:"Avenir", "Helvetica neue", sans-serif;
}

body {
  background: #ffffff;
  color: #555;
}

#title {
	font-size: 40px;
}

h1, body, title {
    color: rgb(100, 100, 100);
    font-weight: normal;
}

h2 {
  font-weight: normal;
}

h3 {
  font-weight: normal;
}

h4 {
  font-weight: normal;
}

h5 {
  font-weight: normal;
}

h6 {
  font-weight: normal;
}

p, li, dd, dt, th, td {
	font-size: 14px;
}

p {
	padding-bottom: 10px;
}

pre {
	padding-top: 0px;
	margin-top: 0px;
}

p:not(.notp){
	text-indent: 0em;
}

a:link {
    color: rgb(22, 123, 204);
}

/* visited link */
a:visited {
    color: rgb(22, 123, 204);
}

/* mouse over link */
a:hover {
    color: rgb(22, 123, 204);
}

/* selected link */
a:active {
    color: rgb(22, 123, 204);
}

th, td {
    padding-right: 10px;
    padding-bottom: 5px;
    vertical-align: top;
}

DELIMITER";
```

## Weaver imports
```d
import globals;
import std.process;
import std.file;
import std.conv;
import std.algorithm;
import std.regex;
import std.path;
import std.stdio;
import std.string;
import parser;
import util;
import dmarkdown;
```

# Tangle

This is the source for tangle. This compiles code from a `.md` file into runnable code.
We do this by going through all the codeblocks, and storing them in an associative array.
Then we apply additions and redefinitions so that the array just contains the code for
each codeblock (indexed with a string: the codeblock name). Then we find the root codeblocks,
i.e. the ones that are a filename, and recursively parse all the codeblocks, following each
link and adding in the code for it.

Here is an overview of the file:

## src/tangler.d
```d
import globals;
import std.string;
import std.stdio;
import parser;
import util;
import std.conv: to;

void tangle(Program p) 
{
    @{The tangle function}
}

@{The writeCode function}
```

## Overview

The `tangle` function will take a program in, go through all the chapters, sections
and find all the codeblocks. It will then apply the codeblock with `+=` and `:=`.
Another thing it must do is find the root blocks, that is, the files that need
to be generated. Starting with those, it will recursively write code to a file using
the `writeCode` function.

## The tangle function

The tangle function should find the codeblocks, apply the `+=` and `:=`, find the
root codeblocks, and call `writeCode` from those.

We'll start with these three variables.

```d
Block[string] rootCodeblocks;
Block[string] codeblocks;

getCodeblocks(p, codeblocks, rootCodeblocks);
```

Now we check if there are any root codeblocks.

## The tangle function +=
```d
if (rootCodeblocks.length == 0) 
{
    warn(p.file, 1, "No file codeblocks, not writing any code");
}
```

Finally we go through every root codeblock, and run writeCode on it. We open a file
(making sure it is in `outDir`). We get the `commentString` from the list of commands.
Then we call `writeCode`, which will recursively follow the links and generate all
the code.

## The tangle function +=
```d
foreach (b; rootCodeblocks) 
{
    string filename = b.name;
    File f;
    if (!noOutput) f = File(outDir ~ "/" ~ filename, "w");
    writeCode(codeblocks, b.name, f, filename, "");
    if (!noOutput) f.close();
}
```

## The writeCode function

The writeCode function recursively follows the links inside a codeblock and writes
all the code for a codeblock. It also keeps the leading whitespace to make sure
indentation in the target file is correct.

```d
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
```

# Main

This file contains the source code for `main.d` the file which contains the
main function for Literate. This will parse any arguments, show help text
and finally run tangle or weave (or both) on any input files.

Here is an overview:

## src/main.d

```d
@{Main imports}

@{getLinenums function}
@{lit function}

void main(in string[] args) 
{
    string[] files = [];
    @{Parse the arguments}
    @{Run Literate}
}
```

## Parsing the Arguments

The arguments will consist of either flags or input files. The flags Literate
accepts are:

* `--help       -h`          Show the help text
* `--tangle     -t`          Only run tangle
* `--weave      -w`          Only run weave
* `--no-output`              Do not generate any output
* `--out-dir    -odir DIR`   Put the generated files in `DIR`
* `--compiler`               Don't ignore the `@compiler` command
* `--linenums -l STR`        Write line numbers prepended with `STR` to the output file
* `--md-compiler COMPILER`   Use the command line program `COMPILER` as the markdown compiler instead of the built-in one
* `--version`                Show the version number and compiler information

All other inputs are input files.

We also need some variables to store these flags in, and they should be global
so that the rest of the program can access them.

## Globals

```d
bool tangleOnly;
bool isBook;
bool weaveOnly;
bool noOutput;
bool noCompCmd = true;
bool tangleErrors;
bool useStdin;
bool lineDirectives;
bool useMdCompiler;
string mdCompilerCmd;
string versionNum = "0.1";
string outDir = "."; // Default is current directory
string lineDirectiveStr;

string helpText = q"DELIMITER
Lit: Literate Programming System

Usage: lit [options] <inputs>

Options:
--help       -h         Show this help text
--tangle     -t         Only compile code files
--weave      -w         Only compile HTML files
--no-output  -no        Do not generate any output files
--out-dir    -odir DIR  Put the generated files in DIR
--compiler   -c         Report compiler errors (needs @compiler to be defined)
--linenums   -l    STR  Write line numbers prepended with STR to the output file
--md-compiler COMPILER  Use COMPILER as the markdown compiler instead of the built-in one
--version    -v         Show the version number and compiler information
DELIMITER";
```

This program uses a number of block modifiers in order to facilitate certain functionality.
i.e. If you don't wish a code block to be woven into the final HTML then the `noWeave`
modifier will indicate this for you.

Each modifier is represented by this list of enums:

## Modifiers

```d
enum Modifier 
{
    noWeave,
    noTangle, // Not yet implemented
    noComment,
    additive, // +=
    redef // :=
}
```

We'll put these two blocks in their own file for "globals".

## src/globals.d
```d
@{Globals}
@{Modifiers}
```

Now, to actually parse the arguments:

## Parse the arguments

```d
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
```

## Run Literate

To run literate we go through every file that was passed in, check if it exists,
and run tangle and weave on it (unless `tangleOnly` or `weaveOnly` was specified).

```d
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
```

The lit function parses the text that is inputted and then either tangles,
weaves, or both. Finally it Checks for compiler errors if the `--compiler` flag
was passed.

## lit function
```d
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
        @{Check for compiler errors}
    }
}
```

## Check for compiler errors

Here we check for compiler errors.

First we have to get all the codeblocks so that we can backtrack the line numbers
from the error message to the correct codeblock. Then we can use the `getLinenums`
function to get the line numbers for each line in the tangled code.

```d
Line[][string] codeLinenums;

Block[string] rootCodeblocks;
Block[string] codeblocks;
getCodeblocks(p, codeblocks, rootCodeblocks);

foreach (b; rootCodeblocks) 
{
    codeLinenums = getLinenums(codeblocks, b.name, b.name, codeLinenums);
}
```

Now we go and check for the `@compiler` command and the `@error_format` command.

## Check for compiler errors +=
```d
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
```

If there is no `@error_format` but the `@compiler` command uses a known compiler, we
can substitute the error format in.

Supported compilers/linters are:

* `clang`
* `gcc`
* `g++`
* `javac`
* `pyflakes`
* `jshint`
* `dmd`

## Check for compiler errors +=
```d
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
```

Now we actually go through and create the regex, by replacing the `%l`, `%f`, and `%m` with
matched regular expressions. Then we execute the shell command, parse each error
using the error format, and rewrite the error with the proper filename and line number
given by the array `codeLinenums` that we created earlier.

## Check for compiler errors +=
```d
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
```

## getLinenums function

Here is the `getLinenums` function. It just goes through every block like tangle would,
but for each line it adds the line to the array, storing the file and
line number for that line.

```d
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
```

Finally, we also have to add the imports.

## Main imports
```d
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
```

# Utilities

This file contains some utilities for the rest of the literate program.

It has functions for reading the entire source of a file, and functions
for reporting errors and warnings.

## src/util.d
```d
import globals;
import std.stdio;
import std.conv;
import parser;
import std.string;
import std.algorithm: canFind;
import std.regex: matchAll, regex;
import std.path;

@{Readall function}
@{error function}
@{warning function}
@{leadingWS function}
@{getCodeblocks function}
@{getChapterHtmlFile function}
```

## Readall function

The `readall` function reads an entire text file, or
reads from stdin until `control-d` is pressed, and returns the string.

```d
// Read from a file
string readall(File file) 
{
    string src = "";
    while (!file.eof) src ~= file.readln(); 
    file.close();
    return src;
}

// Read from stdin
string readall() 
{
    string src = "";
    string line;
    while ((line = readln()) !is null) src ~= line; 
    return src;
}
```

## Error and Warning

These functions simply write errors or warnings to stdout.

### error function
```d
void error(string file, int line, string message) 
{
    writeln(file, ":", line, ":error: ", message);
}
```

### warning function
```d
void warn(string file, int line, string message) 
{
    writeln(file, ":", line, ":warning: ", message);
}
```

## leadingWS function

This function returns the leading whitespace of the input string.

```d
string leadingWS(string str) 
{
    auto firstChar = str.indexOf(strip(str)[0]);
    return str[0..firstChar];
}
```

## getCodeblocks function

`tempCodeblocks` is an array that contains only codeblocks that
have `+=` or `:=`. `rootCodeblocks` and `codeblocks` are both associative arrays
which will hold more important information. `codeblocks` will contain every
codeblock after the `+=` and `:=` transformations have been applied.

Here we go through every single block in the program, and add it to the
`tempCodeblocks` array if it has a `+=` or `:=`. Otherwise, we add it to
the `codeblocks` array, and if it matches the filename regex `.*\.\w+`, we add
it to the `rootCodeblocks` array.

```d
void getCodeblocks(Program p, 
                   out Block[string] codeblocks,
                   out Block[string] rootCodeblocks) 
{
    Block[] tempCodeblocks;

    foreach (c; p.chapters) 
    {
        foreach (s; c.sections) 
        {
            foreach (b; s.blocks) 
            {
                bool isRootBlock = false;
                if (b.isCodeblock) 
                {
                    Block copy = b.dup();
                    auto fileMatch = matchAll(copy.name, regex(".*\\.\\w+"));
                    auto quoteMatch = matchAll(copy.name, regex("^\".*\"$"));
                    if (fileMatch || quoteMatch) 
                    {
                        copy.isRootBlock = true;
                        if (quoteMatch) copy.name = copy.name[1..$-1];   
                    }
                    if ((!copy.modifiers.canFind(Modifier.additive)) && (!copy.modifiers.canFind(Modifier.redef))) 
                    {
                        codeblocks[copy.name] = copy;
                        if (copy.isRootBlock) 
                        {
                            rootCodeblocks[copy.name] = copy;
                        }
                    } 
                    else 
                    {
                        tempCodeblocks ~= copy;
                    }
                }
            }
        }
    }

    // Now we go through every codeblock in tempCodeblocks and apply the += and :=
    foreach (b; tempCodeblocks) 
    {
        if (b.modifiers.canFind(Modifier.additive)) 
        {
            auto index = b.name.length;
            string name = strip(b.name[0..index]);
            if ((name in codeblocks) is null) 
            {
                error(p.file, b.startLine.lineNum, "Trying to add to {" ~ name ~ "} which does not exist");
            } 
            else 
            {
                codeblocks[name].lines ~= b.lines;
            }
        } 
        else if (b.modifiers.canFind(Modifier.redef)) 
        {
            auto index = b.name.length;
            string name = strip(b.name[0..index]);
            if ((name in codeblocks) is null) 
            {
                error(p.file, b.startLine.lineNum, "Trying to redefine {" ~ name ~ "} which does not exist");
            } 
            else 
            {
                codeblocks[name].lines = b.lines;
            }
        }
    }
}
```

## getChapterHtmlFile function

This function returns the html file for a chapter given the major and minor
numbers for it. The minor and major nums are passed in as a string formatted as:
`major.minor`.

```d
string getChapterHtmlFile(Chapter[] chapters, string num) 
{
    string[] nums = num.split(".");
    int majorNum = to!int(nums[0]);
    int minorNum = 0;
    if (nums.length > 1) 
    {
        minorNum = to!int(nums[1]);
    }
    foreach (Chapter c; chapters) 
    {
        if (c.majorNum == majorNum && c.minorNum == minorNum) 
        {
            return stripExtension(baseName(c.file)) ~ ".html";
        }
    }
    return "";
}
```

