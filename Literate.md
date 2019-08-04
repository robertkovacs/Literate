@code_type d .d
@comment_type // %s
@compiler make debug -C ..
@error_format .*/%f\(%l,%s\):%s: %m
@add_css /Users/robert/Literate custom.css

@title Literate

# Introduction

This is an implementation of a literate programming system in D. The goal is to be able to create books that one can read on a website; with chapters, subchapters, and sections, and additionally to be able to compile the code from the book into a working program.

Literate programming aims to make the source code of a program understandable. The program can be structured in any way the programmer likes, and the code should be explained.

The source code for a literate program will somewhat resemble CWEB, but differ in many key ways which simplify the source code and make it easier to read. Literate uses `@` signs for commands and markdown to style the prose.

Here is the full list of features (this is from the [original manual](http://literate.zbyedidia.webfactional.com)):

- supports any language including syntax highlighting and pretty printing
  in HTML;
- generates HTML as output;
- generates readable code and commented in the target language;
- reports syntax errors back from the compiler to the right line in the
  literate source;
- runs fast;
- markdown based - very easy to read and write Literate source;
- automatically generates hyperlinks among code sections;
- formatted output similar to CWEB;
- creates an index with identifiers used (you need to have exuberant or
  universal ctags installed to use this feature);
- supports TeX equations with `$` notation;

# Directory Structure

A literate program may be just a single file, but it should also be possible to make a book out of it, with chapters and possibly multiple programs in a single book. If the literate command line tool is run on a single file, it should compile that file, if it is run on a directory, it should search for the `Summary.md` file in the directory and create a book.

What should the directory structure of a Literate book look like? We try to mimic the [Gitbook](https://github.com/GitbookIO/gitbook) software here. There will be a `Summary.md` file which links to each of the different chapters in the book. An example `Summary.md` file might look like this:

```lit --- Example lit summary ---
    @title Title of the book

    [Chapter 1](chapter1/intro.md)
        [Subchapter 1](chapter1/example1.md)
        [Subchapter 2](chapter1/example2.md)
    [Chapter 2](section2/intro.md)
        [Subchapter 1](chapter2/example1.md)
```

Subchapters are denoted by tabs, and each chapter is linked to the correct `.md` file using Markdown link syntax.

# The Parser

As a first step, I'll make a parser for single chapters only, and leave having multiple chapters and books for later. The parser will have 2 main parts to it: the one which represents the various structures of a literate program, and the parse function.

## src/parser.d

```d --- src/parser.d ---
@{Parser imports}
@{Classes}
@{Parse functions}
```

Let's list the imports here.

## Parser imports

```d --- Parser imports ---
import globals;
import std.stdio;
import util;
import std.string: split, endsWith, startsWith, chomp, replace, strip;
import std.algorithm: canFind;
import std.regex: matchAll, replaceAll, matchFirst, regex, ctRegex, splitter;
import std.conv;
import std.path: extension;
import std.file;
import std.array;
```

## Classes

Now we have to define the classes used to represent a literate program. There are 7 such classes:

```d --- Classes ---
@{Program class}
@{Chapter class}
@{Section class}
@{Block class}
@{Command class}
@{Line class}
@{Change class}
```

### Program class

What is a literate program at the highest level? A program has multiple chapters, it has a title, and it has various commands associated with it (although some of these commands may be overwritten by chapters or even sections).

```d --- Program class ---
class Program 
{
    public string title;
    public Command[] commands;
    public Chapter[] chapters;
```

It also has the file it originally came from.

```d --- Program class --- +=
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

A chapter is very similar to a program. It has a title, commands, sections, and also an original file. In the case of a single file program (which is what we are focusing on for the moment) the Program's file and the Chapter's file will be the same. A chapter also has a minor number and a major number.

(TODO: this major-minor number system needs to be extended to allow multiple levels at the book level too.)

```d --- Chapter class ---
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

A section has a title, commands, a number, and a series of blocks, which can either be blocks of code, or blocks of prose.

We can also attribute a level to sections which allows us to organize our sections hierarchically. Six levels are supported at the moment; in the final  document these are translated to HTML tags `&lt;h1&gt;` to `&lt;h6&gt;`.

Accordingly, the section number is an array of six numbers in fact. 

```d --- Section class ---

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

    @{numToString method}
}
```

Two support functions are needed to handle the number array seamlessly:

* First we need a function to convert this array to a string - the `numToString` class method does this for us. The only trick we need to consider here is not to include trailing zeros to our result string.

```d --- numToString method ---

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
```

* Second, we need a function to increase the numbering according to the section's level. The `increaseSectionNum` function called during chapter parsing (i.e. in the `parseChapter` call) is responsible for this (for more details see the description of `parseChapter`).


### Block class

A block is more interesting. It can either be a block of code, or a block of prose, so it has a boolean which represents what type it is. It also stores a start line. If it is a code block, it also has a name. Finally, it stores an array of lines, and has a function called `text()` which just returns the string of the text it contains. A block also contains a `codeType` and a `commentString`.

```d --- Block class ---
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

```d --- Command class ---
class Command 
{
    public string name;
    public string args;
    public int lineNum;
    public string filename;
}
```

### Line class

A line is the lowest level. It stores the line number, the file the line is from, and the text for the line itself.

```d --- Line class ---

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

The change class helps when parsing a change statement (more information on the change statement is available in section [Parse change block](#parse-change-block). It stores the file that is being changed, what the text to search for is and what the text to replace it with is. These two things are arrays because you can make multiple changes (search and replaces) to one file. In order to keep track of the current change, an index is also stored.

```d --- Change class ---
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


That's it for the classes. These 7 classes can be used to represent an entire literate program. Now let's get to the actual parse function to turn a text file into a program.

## Parse functions

Here we have two functions: `parseProgram` and `parseChapter`.

```d --- Parse functions ---

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

```d --- parseProgram function ---
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

The `parseChapter` function is the more complex one. It parses the source of a 
chapter. Before doing any parsing, we resolve the `@include` statements by
replacing them with the contents of the file that was included. Then we loop 
through each line in the source and parse it, provided that it is not a 
comment (starting with `//`);

```d --- parseChapter function ---

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
    src = replaceAll!(match => include(match[1]))(src, regex(`\n@include (.*)`));
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

### The parse function setup

For the initial variables, it would be nice to move the value for `chapter.file` into a variable called `filename`. Additionally, I'm going to need an array of all the possible commands that are recognized.

```d --- Initialize some variables ---
string filename = chapter.file;
string[] commands = ["@code_type", "@comment_type", "@compiler", "@error_format",
                     "@add_css", "@overwrite_css", "@colorscheme", "@include"];
```

We also need to keep track of the current section that is being parsed, and the current block that is being parsed, because the parser is going through the file one line at a time. We'll also define the current change being parsed.

```d --- Initialize some variables --- +=
Section curSection;
int[6] sectionNum = [0, 0, 0, 0, 0, 0];
Block curBlock;
Change curChange;
```

Finally, 3 flags are needed to keep track of if it is currently parsing a codeblock, a search block, or a replace block.

```d --- Initialize some variables --- +=
bool inCodeblock = false;
bool inSearchBlock = false;
bool inReplaceBlock = false;
```

### Parse the line

When parsing a line, we are either inside a code block, or inside a prose block, or we are transitioning from one to the other. So we'll have an if statement to separate the two.

```d --- Parse the line ---
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

Parsing a command and the title command are both fairly simple, so let's look at those first.

To parse a command we first make sure that there is the command name, and any arguments. Then we check if the command is part of the list of commands we have. If it is, we create a new command object, fill in the name and arguments, and add it to the chapter object.

We also do something special if it is an `@include` command. For these ones, we take the file, read it, and parse it as a chapter (using the `parseChapter` function). Then we add the included chapter's sections to the current chapter's sections. In this case, we don't add the `@include` command to the list of chapter commands.

#### Parse a command
```d --- Parse a command ---
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
```d --- Parse a title command ---
if (startsWith(line, "@title")) 
{
    chapter.title = strip(line[6..$]);
}
```

### Parse a section definition

When a new section is created (using `#` .. `######`), we should add the current section to the list of sections for the chapter, and then we should create a new section, which becomes the current one.

```d --- Parse a section definition ---
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

Section number increase - since we support six levels of sections to have a hierarchical structure even inside a chapter - depends on the section's level. When we increase the number of a certain level, all lower levels need to be zeroed out. The `increaseSectionNum` function does this job for us.

```d --- Increase section number ---
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

Codeblocks always begin with three backticks, so we can use a proper regex to represent this. Once a new codeblock starts, the old one must be appended to the current section's list of blocks, and the current codeblock must be reset.

```d --- Parse the beginning of a code block ---
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
    // curBlock.name = curSection.title;

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

### Check for and extract modifiers

Modifier format for a code block: `--- Block name --- noWeave +=`. The `checkForModifiers` ugliness is due to lack of `(?|...)` and friends.

First half matches for expressions *with* modifiers:

1. `(?P<namea>\S.*)` : Keep taking from the first non-whitespace character ...
2. `[ \t]-{3}[ \t]` : Until it matches ` --- `
3. `(?P<modifiers>.+)` : Matches everything after the separator.

Second half matches for no modifiers: Ether `Block name` and with a floating separator `Block Name ---`.

1. `|(?P<nameb>\S.*?)` : Same thing as #1 but stores it in `nameb`
2. `[ \t]*?` : Checks for any amount of whitespace (Including none.)
3. `(-{1,}$` : Checks for any floating `-` and verifies that nothing else is there until end of line.
4. `|$))` : Or just checks that there is nothing but the end of the line after the whitespace.

Returns either `namea` and `modifiers` or just `nameb`, this way 

```d --- Parse Modifiers ---
// auto checkForModifiers = ctRegex!(`[ \t]-{3}[ \t](?P<namea>\S.*)[ \t]-{3}[ \t](?P<modifiers>.+)|(?P<nameb>\S.*?)[ \t]*?(-{1,}$|$)`);
auto checkForModifiers = ctRegex!(r"```[\S]+[ \t]-{3}[ \t](?P<namea>.+)[ \t]-{3}[ \t](?P<modifiers>.+)|```[\S]+[ \t]-{3}[ \t](?P<nameb>\S.*?)[ \t]*?(-{1,}$|$)");
auto splitOnSpace = ctRegex!(r"(\s+)");
auto modMatch = matchFirst(curBlock.startLine.text, checkForModifiers);
```

These two are here just for debugging purposes.

```d --- Parse Modifiers --- +=
// writeln("namea: ", modMatch["namea"]);
// writeln("nameb: ", modMatch["nameb"]);
```

`matchFirst` returns unmatched groups as empty strings.

```d --- Parse Modifiers --- +=

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

```d --- Begin a new prose block ---
if (curBlock !is null) curSection.blocks ~= curBlock;
curBlock = new Block();
curBlock.startLine = lineObj;
curBlock.isCodeblock = false;
inCodeblock = false;
```

### Add the current line

Finally, if the current line is nothing interesting, we just add it to the current block's
list of lines.

```d --- Add the line to the list of lines ---
curBlock.lines ~= new Line(line, filename, lineNum);
```

Now we're done parsing the line.

### Close the last section

When the end of the file is reached, the last section has not been closed and added to the
chapter yet, so we should do that. Additionally, if the last block is a prose block, it should
be closed and added to the section first. If the last block is a code block, it should have been
closed with three backticks. If it was not, we throw an error.

```d --- Close the last section ---
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

```lit --- Change block - example ---

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
```

You can make multiple changes on one file. We've got two nice flags for keeping track of which kind of block we are in: replaceText or searchText.

```d --- Parse change block ---

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

Here is an overview of the weave functionality. Here we turn a literate source file into one or more Markdown files. The Markdown files created contain proper cross references, references to code blocks and can be converted into HTML, PDF or any other output formats by e.g. `pandoc`.

```d --- src/weaver.d ---
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

Now we parse the codeblocks across all chapters in the program. We have four arrays:

* defLocations: stores the section in which a codeblock is defined.
* redefLocations: stores the sections in which a codeblock is redefined.
* addLocations: stores the sections in which a codeblock is added to.
* useLocations: stores the sections in which a codeblock is used;

```d --- Parse use locations ---
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

Here we simply loop through all the chapters in the program and get the Markdown for them. If `noOutput` is false, we generate HTML files in the `outDir`.

```d --- Run weaveChapter ---
foreach (chapter; p.chapters) 
{
    string output = weaveChapter(chapter, p, defLocations, redefLocations,
                                 addLocations, useLocations);
    if (!noOutput) 
    {
        string dir = outDir;
        if (isBook) 
        {
            dir = outDir ~ "/_book";
            if (!dir.exists()) mkdir(dir);
        }
        File f = File(dir ~ "/" ~ stripExtension(baseName(chapter.file)) ~ ".html", "w");
        f.write(output);
        f.close();
    }
}
```

## Table of contents

If the program being compiled is a book, we should also write a table of contents file. 

```d --- Create the table of contents ---
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

## Root code block check

We check if the block is a root code block: we check this using a regex that basically checks if it the name has an extension. Additionally, users can put the block name in quotes to force it to be a root code block.

If the block name is in quotes, we have to make sure to remove those once we're done.

```d --- Check if it's a root block ---
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

```d --- WeaveChapter ---
string weaveChapter(Chapter c, Program p, string[string] defLocations,
                    string[][string] redefLocations, string[][string] addLocations,
                    string[][string] useLocations) 
{
@{prettify}
@{css}

    string output;

@{Write the head of the HTML}
@{Write the body}

	if (use_katex) 
	{
@{Write the katex source}
@{Process math by katex}
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

This writes out the start of the document. Mainly the scripts (prettify.js) and the css (prettify css, default css, and colorscheme css). It also adds the title of the document.

```d --- Write the head of the HTML ---
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

Now we write the body -- this is the meat of the weaver. First we write a couple things at the beginning: making sure the `prettyprint` function is called when the page loads, and writing out the title as a `p`.

```d --- Write the body ---
output ~= q"DELIMITER
<body onload="prettyPrint()"  data-spy="scroll" data-target="#toc">
<div class="row">
<div class="col-sm-3">
<nav id="toc" data-spy="affix" data-toggle="toc"></nav>
</div>
<div class="col-sm-9">
DELIMITER";
output ~= "<p id=\"title\">" ~ c.title ~ "</p>";
```

Then we loop through each section in the chapter. At the beginning of each section, we write the title, and an empty `a` link so that the section title can be linked to.

We also have to determine if the section title should be a `noheading` class. If the section title is empty, then the class should be `noheading` which means that the prose will be moved up a bit towards it -- otherwise it looks like there is too much empty space between the title and the prose.

```d --- Write the body --- +=
foreach (section; c.sections) 
{
	string noheading = section.title == "" ? " class=\"noheading\"" : "";
```

Then, we create an anchor for the headings. The anchor text is the section title in lower case, and with spaces converted to hyphens.

```d --- Write the body --- +=
    string sectionID = section.title.strip.toLower.replace(" ", "-");
    string sectionIDAttribute = " id=\"" ~ sectionID ~ "\"";
	if (!section.title.endsWith("+="))
	{
        output ~= "<a name=\"" ~ c.num() ~ ":" ~ section.numToString() ~ "\"><div class=\"section\"><h" ~ to!string(section.level + 1) ~
                  noheading ~ sectionIDAttribute ~ ">" ~ section.numToString() ~ ". " ~ section.title ~ "</h" ~ to!string(section.level + 1) ~ "></a>\n";
    }
    
    foreach (block; section.blocks) 
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

Weaving a prose block is not very complicated: 

Here we use the same regex to actually perform the substitution. Double dollars mean a block math which means we have to use a div. For inline math (single dollars) we use a span. After that substitution we replace all backslash dollars to real dollar signs.

Finally we add this html to the output and add a newline for good measure.

```d --- Weave a prose block ---
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
```

Here we have a few regexes that needs some further explanations. Let's analyze the first one: 

```regex --- Double dollar math regex ---
(?<!\\)[\$](?<!\\)[\$](.*?)(?<!\\)[\$](?<!\\)[\$]
```

The part 

```regex --- Dollar with no preceding backslash regex ---
(?<!\\)[\$]
```

is a negative lookbehind, that matches all dollars, not preceded by backslashes. We have two of these constructs at the beginning, and then two at the end. In the middle, we match literally anything, but in a lazy way. This means that this regex matches expressions like `\$\$a = 1\$\$` (i.e. anything between two dollar signs.).

The second expression does a similar thing for math expressions with single dollar signs (`\$a=1\$`). So here we detect whether we need to use KaTeX.

```d --- Weave a prose block --- +=

auto doubleDollarMathNotation = regex(r"(?<!\\)[\$](?<!\\)[\$](?P<formula>.*?)(?<!\\)[\$](?<!\\)[\$]");
auto singleDollarMathNotation = regex(r"(?<!\\)[\$](?P<formula>.*?)(?<!\\)[\$]");

if (md.matchAll(doubleDollarMathNotation) || md.matchAll(singleDollarMathNotation)) 
{
    use_katex = true;
}
```

Then, we mark math text by class="math" in the HTML tags. Double dollar notation gets transformed into a `div`, whereas single dollar notation gets transferred into `span`.

```d --- Weave a prose block --- +=
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

Hm, why did we separate this guy below? ...

```d --- Weave a prose block --- +=
output ~= html ~ "\n";
```

## Weave a code block

```d --- Weave a code block ---
output ~= "<div class=\"codeblock\">\n";

@{Write the title out}
@{Write the actual code}
@{Write the 'added to' links}
@{Write the 'redefined in' links}
@{Write the 'used in' links}

output ~= "</div>\n";
```

### The codeblock title

Here we create the title for the codeblock. For the title, we have to link to the definition (which is usually the current block, but sometimes not, because of `+=`). We also need to make the title bold (`&lt;strong&gt;`) if it is a root code block.

```d --- Write the title out ---
@{Find the definition location}
@{Make the title bold if necessary}

output ~= "<span class=\"codeblock_name\">{" ~ name ~
          " <a href=\"" ~ htmlFile ~ "#" ~ def ~ "\">" ~ defLocation ~ "</a>}" ~ extra ~ "</span>\n";
```

To find the definition location we use the handy `defLocation` array that we made earlier. The reason we have both the variables `def` and `defLocation` is because the definition location might be in another chapter, in which case it should be displayed as `chapterNum:sectionNum` but if it's in the current file, the `chapterNum` can be removed. `def` gives us the real definition location, and `defLocation` is the one that will be used -- it strips out the `chapterNum` if necessary.

```d --- Find the definition location ---
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

We also add the `+=` or `:=` if necessary. This needs to be the `extra` because it goes outside the `{}` and is not really part of the name anymore.

```d --- Find the definition location --- +=
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

```d --- Make the title bold if necessary ---
string name;
if (block.isRootBlock) name = "<strong>" ~ block.name ~ "</strong>";
else name = block.name;

```

### The actual code

At the beginning, we open the pre tag. If a codetype is defined, we tell the prettyprinter to use that, otherwise, the pretty printer will try to figure out how to syntax highlight on its own -- and it's pretty good at that.

```d --- Write the actual code ---
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

Now we loop through each line. The only complicated thing here is if the line is a codeblock use. Then we have to link to the correct definition location.

Also we escape all ampersands and greater than and less than signs before writing them.

```d --- Write the line ---
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

For linking the used codeblock, it's pretty much the same deal as before. We reuse the `def` and `defLocation` variables. We also write the final html as a span with the `nocode` class, that way it won't be syntax highlighted by the pretty printer.

```d --- Link a used codeblock ---
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

Writing the links is pretty similar to figuring out where a codeblock was defined because we have access to the `sectionLocations` array (which is `addLocations`, `useLocations`, or `redefLocations`). Then we just have a few if statements to figure out the grammar -- where to put the `and` and whether to have plurals and whatnot.

```d --- LinkLocations function ---
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

Writing the 'added to' links is pretty similar to figuring out where a codeblock was defined because we have access to the `addLocations` array. Then we just have a few if statements to figure out the grammar -- where to put the `and` and whether to have plurals and whatnot.

```d --- Write the 'added to' links ---
output ~= linkLocations("Added to in section", addLocations, p, c, section, block) ~ "\n";
```

### Also used in links

This is pretty much the same as the 'added to' links except we use the `useLocations` array.

```d --- Write the 'used in' links ---
output ~= linkLocations("Used in section", useLocations, p, c, section, block) ~ "\n";
```

### Redefined in links

```d --- Write the 'redefined in' links ---
output ~= linkLocations("Redefined in section", redefLocations, p, c, section, block) ~ "\n";
```

## Katex source

This is the source code for katex which should only be used if math is used in the literate file. We include a script which uses the cdn first because that will use better fonts, however it needs the user to be connected to the internet. In the case that the user is offline, we include the entire source for katex, but it will use worse fonts (still better than nothing though).

```d --- Write the katex source ---
output ~= "<link rel=\"stylesheet\" href=\"https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.10.1/katex.min.css\">\n" ~
"<script src=\"https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.10.1/katex.min.js\"></script>\n";
```

Then we loop over all the math divs and spans and render by katex.

```d --- Process math by katex ---
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

## prettify

This is the Javascript component used for source code syntax highlighting. It would be just great to annotate this code too, but for now this seems to be out of scope for this project. It would be great however to dig a source of this code on the internet.

```d --- prettify ---
string prettify = q"DELIMITER
! function ()
{
	var q = null;
	window.PR_SHOULD_USE_CONTINUATION = !0;
	(function ()
	{
		function R(a)
		{
			function d(e)
			{
				var b = e.charCodeAt(0);
				if (b !== 92) return b;
				var a = e.charAt(1);
				return (b = r[a]) ? b : "0" <= a && a <= "7" ? parseInt(e.substring(1), 8) : a === "u" || a === "x" ? parseInt(e.substring(2), 16) : e.charCodeAt(1)
			}

			function g(e)
			{
				if (e < 32) return (e < 16 ? "\\x0" : "\\x") + e.toString(16);
				e = String.fromCharCode(e);
				return e === "\\" || e === "-" || e === "]" || e === "^" ? "\\" + e : e
			}

			function b(e)
			{
				var b = e.substring(1, e.length - 1).match(/\\u[\dA-Fa-f]{4}|\\x[\dA-Fa-f]{2}|\\[0-3][0-7]{0,2}|\\[0-7]{1,2}|\\[\S\s]|[^\\]/g),
					e = [],
					a =
					b[0] === "^",
					c = ["["];
				a && c.push("^");
				for (var a = a ? 1 : 0, f = b.length; a < f; ++a)
				{
					var h = b[a];
					if (/\\[bdsw]/i.test(h)) c.push(h);
					else
					{
						var h = d(h),
							l;
						a + 2 < f && "-" === b[a + 1] ? (l = d(b[a + 2]), a += 2) : l = h;
						e.push([h, l]);
						l < 65 || h > 122 || (l < 65 || h > 90 || e.push([Math.max(65, h) | 32, Math.min(l, 90) | 32]), l < 97 || h > 122 || e.push([Math.max(97, h) & -33, Math.min(l, 122) & -33]))
					}
				}
				e.sort(function (e, a)
				{
					return e[0] - a[0] || a[1] - e[1]
				});
				b = [];
				f = [];
				for (a = 0; a < e.length; ++a) h = e[a], h[0] <= f[1] + 1 ? f[1] = Math.max(f[1], h[1]) : b.push(f = h);
				for (a = 0; a < b.length; ++a) h = b[a], c.push(g(h[0])),
					h[1] > h[0] && (h[1] + 1 > h[0] && c.push("-"), c.push(g(h[1])));
				c.push("]");
				return c.join("")
			}

			function s(e)
			{
				for (var a = e.source.match(/\[(?:[^\\\] ]|\\[\S\s])*]|\\u[\dA-Fa-f]{4}|\\x[\dA-Fa-f]{2}|\\\d+|\\[^\dux]|\(\?[!:=]|[()^]|[^()[\\^]+/g), c = a.length, d = [], f = 0, h = 0; f < c; ++f)
				{
					var l = a[f];
					l === "(" ? ++h : "\\" === l.charAt(0) && (l = +l.substring(1)) && (l <= h ? d[l] = -1 : a[f] = g(l))
				}
				for (f = 1; f < d.length; ++f) - 1 === d[f] && (d[f] = ++x);
				for (h = f = 0; f < c; ++f) l = a[f], l === "(" ? (++h, d[h] || (a[f] = "(?:")) : "\\" === l.charAt(0) && (l = +l.substring(1)) && l <= h &&
					(a[f] = "\\" + d[l]);
				for (f = 0; f < c; ++f) "^" === a[f] && "^" !== a[f + 1] && (a[f] = "");
				if (e.ignoreCase && m)
					for (f = 0; f < c; ++f) l = a[f], e = l.charAt(0), l.length >= 2 && e === "[" ? a[f] = b(l) : e !== "\\" && (a[f] = l.replace(/[A-Za-z]/g, function (a)
					{
						a = a.charCodeAt(0);
						return "[" + String.fromCharCode(a & -33, a | 32) + "]"
					}));
				return a.join("")
			}
			for (var x = 0, m = !1, j = !1, k = 0, c = a.length; k < c; ++k)
			{
				var i = a[k];
				if (i.ignoreCase) j = !0;
				else if (/[a-z]/i.test(i.source.replace(/\\u[\da-f]{4}|\\x[\da-f]{2}|\\[^UXux]/gi, "")))
				{
					m = !0;
					j = !1;
					break
				}
			}
			for (var r = {
					b: 8,
					t: 9,
					n: 10,
					v: 11,
					f: 12,
					r: 13
				}, n = [], k = 0, c = a.length; k < c; ++k)
			{
				i = a[k];
				if (i.global || i.multiline) throw Error("" + i);
				n.push("(?:" + s(i) + ")")
			}
			return RegExp(n.join("|"), j ? "gi" : "g")
		}

		function S(a, d)
		{
			function g(a)
			{
				var c = a.nodeType;
				if (c == 1)
				{
					if (!b.test(a.className))
					{
						for (c = a.firstChild; c; c = c.nextSibling) g(c);
						c = a.nodeName.toLowerCase();
						if ("br" === c || "li" === c) s[j] = "\n", m[j << 1] = x++, m[j++ << 1 | 1] = a
					}
				}
				else if (c == 3 || c == 4) c = a.nodeValue, c.length && (c = d ? c.replace(/\r\n?/g, "\n") : c.replace(/[\t\n\r ]+/g, " "), s[j] = c, m[j << 1] = x, x += c.length, m[j++ << 1 | 1] =
					a)
			}
			var b = /(?:^|\s)nocode(?:\s|$)/,
				s = [],
				x = 0,
				m = [],
				j = 0;
			g(a);
			return {
				a: s.join("").replace(/\n$/, ""),
				d: m
			}
		}

		function H(a, d, g, b)
		{
			d && (a = {
				a: d,
				e: a
			}, g(a), b.push.apply(b, a.g))
		}

		function T(a)
		{
			for (var d = void 0, g = a.firstChild; g; g = g.nextSibling) var b = g.nodeType,
				d = b === 1 ? d ? a : g : b === 3 ? U.test(g.nodeValue) ? a : d : d;
			return d === a ? void 0 : d
		}

		function D(a, d)
		{
			function g(a)
			{
				for (var j = a.e, k = [j, "pln"], c = 0, i = a.a.match(s) || [], r = {}, n = 0, e = i.length; n < e; ++n)
				{
					var z = i[n],
						w = r[z],
						t = void 0,
						f;
					if (typeof w === "string") f = !1;
					else
					{
						var h = b[z.charAt(0)];
						if (h) t = z.match(h[1]), w = h[0];
						else
						{
							for (f = 0; f < x; ++f)
								if (h = d[f], t = z.match(h[1]))
								{
									w = h[0];
									break
								}
							t || (w = "pln")
						}
						if ((f = w.length >= 5 && "lang-" === w.substring(0, 5)) && !(t && typeof t[1] === "string")) f = !1, w = "src";
						f || (r[z] = w)
					}
					h = c;
					c += z.length;
					if (f)
					{
						f = t[1];
						var l = z.indexOf(f),
							B = l + f.length;
						t[2] && (B = z.length - t[2].length, l = B - f.length);
						w = w.substring(5);
						H(j + h, z.substring(0, l), g, k);
						H(j + h + l, f, I(w, f), k);
						H(j + h + B, z.substring(B), g, k)
					}
					else k.push(j + h, w)
				}
				a.g = k
			}
			var b = {},
				s;
			(function ()
			{
				for (var g = a.concat(d), j = [], k = {}, c = 0, i = g.length; c < i; ++c)
				{
					var r =
						g[c],
						n = r[3];
					if (n)
						for (var e = n.length; --e >= 0;) b[n.charAt(e)] = r;
					r = r[1];
					n = "" + r;
					k.hasOwnProperty(n) || (j.push(r), k[n] = q)
				}
				j.push(/[\S\s]/);
				s = R(j)
			})();
			var x = d.length;
			return g
		}

		function v(a)
		{
			var d = [],
				g = [];
			a.tripleQuotedStrings ? d.push(["str", /^(?:'''(?:[^'\\]|\\[\S\s]|''?(?=[^']))*(?:'''|$)|"""(?:[^"\\]|\\[\S\s]|""?(?=[^"]))*(?:"""|$)|'(?:[^'\\]|\\[\S\s])*(?:'|$)|"(?:[^"\\]|\\[\S\s])*(?:"|$))/, q, "'\""]) : a.multiLineStrings ? d.push(["str", /^(?:'(?:[^'\\]|\\[\S\s])*(?:'|$)|"(?:[^"\\]|\\[\S\s])*(?:"|$)|`(?:[^\\`]|\\[\S\s])*(?:`|$))/,
				q, "'\"`"
			]) : d.push(["str", /^(?:'(?:[^\n\r'\\]|\\.)*(?:'|$)|"(?:[^\n\r"\\]|\\.)*(?:"|$))/, q, "\"'"]);
			a.verbatimStrings && g.push(["str", /^@"(?:[^"]|"")*(?:"|$)/, q]);
			var b = a.hashComments;
			b && (a.cStyleComments ? (b > 1 ? d.push(["com", /^#(?:##(?:[^#]|#(?!##))*(?:###|$)|.*)/, q, "#"]) : d.push(["com", /^#(?:(?:define|e(?:l|nd)if|else|error|ifn?def|include|line|pragma|undef|warning)\b|[^\n\r]*)/, q, "#"]), g.push(["str", /^<(?:(?:(?:\.\.\/)*|\/?)(?:[\w-]+(?:\/[\w-]+)+)?[\w-]+\.h(?:h|pp|\+\+)?|[a-z]\w*)>/, q])) : d.push(["com",
				/^#[^\n\r]*/, q, "#"
			]));
			a.cStyleComments && (g.push(["com", /^\/\/[^\n\r]*/, q]), g.push(["com", /^\/\*[\S\s]*?(?:\*\/|$)/, q]));
			if (b = a.regexLiterals)
			{
				var s = (b = b > 1 ? "" : "\n\r") ? "." : "[\\S\\s]";
				g.push(["lang-regex", RegExp("^(?:^^\\.?|[+-]|[!=]=?=?|\\#|%=?|&&?=?|\\(|\\*=?|[+\\-]=|->|\\/=?|::?|<<?=?|>>?>?=?|,|;|\\?|@|\\[|~|{|\\^\\^?=?|\\|\\|?=?|break|case|continue|delete|do|else|finally|instanceof|return|throw|try|typeof)\\s*(" + ("/(?=[^/*" + b + "])(?:[^/\\x5B\\x5C" + b + "]|\\x5C" + s + "|\\x5B(?:[^\\x5C\\x5D" + b + "]|\\x5C" +
					s + ")*(?:\\x5D|$))+/") + ")")])
			}(b = a.types) && g.push(["typ", b]);
			b = ("" + a.keywords).replace(/^ | $/g, "");
			b.length && g.push(["kwd", RegExp("^(?:" + b.replace(/[\s,]+/g, "|") + ")\\b"), q]);
			d.push(["pln", /^\s+/, q, " \r\n\t "]);
			b = "^.[^\\s\\w.$@'\"`/\\\\]*";
			a.regexLiterals && (b += "(?!s*/)");
			g.push(["lit", /^@[$_a-z][\w$@]*/i, q], ["typ", /^(?:[@_]?[A-Z]+[a-z][\w$@]*|\w+_t\b)/, q], ["pln", /^[$_a-z][\w$@]*/i, q], ["lit", /^(?:0x[\da-f]+|(?:\d(?:_\d+)*\d*(?:\.\d*)?|\.\d\+)(?:e[+-]?\d+)?)[a-z]*/i, q, "0123456789"], ["pln", /^\\[\S\s]?/,
				q
			], ["pun", RegExp(b), q]);
			return D(d, g)
		}

		function J(a, d, g)
		{
			function b(a)
			{
				var c = a.nodeType;
				if (c == 1 && !x.test(a.className))
					if ("br" === a.nodeName) s(a), a.parentNode && a.parentNode.removeChild(a);
					else
						for (a = a.firstChild; a; a = a.nextSibling) b(a);
				else if ((c == 3 || c == 4) && g)
				{
					var d = a.nodeValue,
						i = d.match(m);
					if (i) c = d.substring(0, i.index), a.nodeValue = c, (d = d.substring(i.index + i[0].length)) && a.parentNode.insertBefore(j.createTextNode(d), a.nextSibling), s(a), c || a.parentNode.removeChild(a)
				}
			}

			function s(a)
			{
				function b(a, c)
				{
					var d =
						c ? a.cloneNode(!1) : a,
						e = a.parentNode;
					if (e)
					{
						var e = b(e, 1),
							g = a.nextSibling;
						e.appendChild(d);
						for (var i = g; i; i = g) g = i.nextSibling, e.appendChild(i)
					}
					return d
				}
				for (; !a.nextSibling;)
					if (a = a.parentNode, !a) return;
				for (var a = b(a.nextSibling, 0), d;
					(d = a.parentNode) && d.nodeType === 1;) a = d;
				c.push(a)
			}
			for (var x = /(?:^|\s)nocode(?:\s|$)/, m = /\r\n?|\n/, j = a.ownerDocument, k = j.createElement("li"); a.firstChild;) k.appendChild(a.firstChild);
			for (var c = [k], i = 0; i < c.length; ++i) b(c[i]);
			d === (d | 0) && c[0].setAttribute("value", d);
			var r = j.createElement("ol");
			r.className = "linenums";
			for (var d = Math.max(0, d - 1 | 0) || 0, i = 0, n = c.length; i < n; ++i) k = c[i], k.className = "L" + (i + d) % 10, k.firstChild || k.appendChild(j.createTextNode(" ")), r.appendChild(k);
			a.appendChild(r)
		}

		function p(a, d)
		{
			for (var g = d.length; --g >= 0;)
			{
				var b = d[g];
				F.hasOwnProperty(b) ? E.console && console.warn("cannot override language handler %s", b) : F[b] = a
			}
		}

		function I(a, d)
		{
			if (!a || !F.hasOwnProperty(a)) a = /^\s*</.test(d) ? "default-markup" : "default-code";
			return F[a]
		}

		function K(a)
		{
			var d = a.h;
			try
			{
				var g = S(a.c, a.i),
					b = g.a;
				a.a = b;
				a.d = g.d;
				a.e = 0;
				I(d, b)(a);
				var s = /\bMSIE\s(\d+)/.exec(navigator.userAgent),
					s = s && +s[1] <= 8,
					d = /\n/g,
					x = a.a,
					m = x.length,
					g = 0,
					j = a.d,
					k = j.length,
					b = 0,
					c = a.g,
					i = c.length,
					r = 0;
				c[i] = m;
				var n, e;
				for (e = n = 0; e < i;) c[e] !== c[e + 2] ? (c[n++] = c[e++], c[n++] = c[e++]) : e += 2;
				i = n;
				for (e = n = 0; e < i;)
				{
					for (var p = c[e], w = c[e + 1], t = e + 2; t + 2 <= i && c[t + 1] === w;) t += 2;
					c[n++] = p;
					c[n++] = w;
					e = t
				}
				c.length = n;
				var f = a.c,
					h;
				if (f) h = f.style.display, f.style.display = "none";
				try
				{
					for (; b < k;)
					{
						var l = j[b + 2] || m,
							B = c[r + 2] || m,
							t = Math.min(l, B),
							A = j[b + 1],
							G;
						if (A.nodeType !== 1 && (G = x.substring(g,
								t)))
						{
							s && (G = G.replace(d, "\r"));
							A.nodeValue = G;
							var L = A.ownerDocument,
								o = L.createElement("span");
							o.className = c[r + 1];
							var v = A.parentNode;
							v.replaceChild(o, A);
							o.appendChild(A);
							g < l && (j[b + 1] = A = L.createTextNode(x.substring(t, l)), v.insertBefore(A, o.nextSibling))
						}
						g = t;
						g >= l && (b += 2);
						g >= B && (r += 2)
					}
				}
				finally
				{
					if (f) f.style.display = h
				}
			}
			catch (u)
			{
				E.console && console.log(u && u.stack || u)
			}
		}
		var E = window,
			y = ["break,continue,do,else,for,if,return,while"],
			C = [
				[y, "auto,case,char,const,default,double,enum,extern,float,goto,inline,int,long,register,short,signed,sizeof,static,struct,switch,typedef,union,unsigned,void,volatile"],
				"catch,class,delete,false,import,new,operator,private,protected,public,this,throw,true,try,typeof"
			],
			M = [C, "alignof,align_union,asm,axiom,bool,concept,concept_map,const_cast,constexpr,decltype,delegate,dynamic_cast,explicit,export,friend,generic,late_check,mutable,namespace,nullptr,property,reinterpret_cast,static_assert,static_cast,template,typeid,typename,using,virtual,where"],
			V = [C, "abstract,assert,boolean,byte,extends,final,finally,implements,import,instanceof,interface,null,native,package,strictfp,super,synchronized,throws,transient"],
			N = [C, "abstract,as,base,bool,by,byte,checked,decimal,delegate,descending,dynamic,event,finally,fixed,foreach,from,group,implicit,in,interface,internal,into,is,let,lock,null,object,out,override,orderby,params,partial,readonly,ref,sbyte,sealed,stackalloc,string,select,uint,ulong,unchecked,unsafe,ushort,var,virtual,where"],
			C = [C, "debugger,eval,export,function,get,null,set,undefined,var,with,Infinity,NaN"],
			O = [y, "and,as,assert,class,def,del,elif,except,exec,finally,from,global,import,in,is,lambda,nonlocal,not,or,pass,print,raise,try,with,yield,False,True,None"],
			P = [y, "alias,and,begin,case,class,def,defined,elsif,end,ensure,false,in,module,next,nil,not,or,redo,rescue,retry,self,super,then,true,undef,unless,until,when,yield,BEGIN,END"],
			W = [y, "as,assert,const,copy,drop,enum,extern,fail,false,fn,impl,let,log,loop,match,mod,move,mut,priv,pub,pure,ref,self,static,struct,true,trait,type,unsafe,use"],
			y = [y, "case,done,elif,esac,eval,fi,function,in,local,set,then,until"],
			Q = /^(DIR|FILE|vector|(de|priority_)?queue|list|stack|(const_)?iterator|(multi)?(set|map)|bitset|u?(int|float)\d*)\b/,
			U = /\S/,
			X = v(
			{
				keywords: [M, N, C, "caller,delete,die,do,dump,elsif,eval,exit,foreach,for,goto,if,import,last,local,my,next,no,our,print,package,redo,require,sub,undef,unless,until,use,wantarray,while,BEGIN,END", O, P, y],
				hashComments: !0,
				cStyleComments: !0,
				multiLineStrings: !0,
				regexLiterals: !0
			}),
			F = {};
		p(X, ["default-code"]);
		p(D([], [
			["pln", /^[^<?]+/],
			["dec", /^<!\w[^>]*(?:>|$)/],
			["com", /^<\!--[\S\s]*?(?:--\>|$)/],
			["lang-", /^<\?([\S\s]+?)(?:\?>|$)/],
			["lang-", /^<%([\S\s]+?)(?:%>|$)/],
			["pun", /^(?:<[%?]|[%?]>)/],
			["lang-",
				/^<xmp\b[^>]*>([\S\s]+?)<\/xmp\b[^>]*>/i
			],
			["lang-js", /^<script\b[^>]*>([\S\s]*?)(<\/script\b[^>]*>)/i],
			["lang-css", /^<style\b[^>]*>([\S\s]*?)(<\/style\b[^>]*>)/i],
			["lang-in.tag", /^(<\/?[a-z][^<>]*>)/i]
		]), ["default-markup", "htm", "html", "mxml", "xhtml", "xml", "xsl"]);
		p(D([
			["pln", /^\s+/, q, " \t\r\n"],
			["atv", /^(?:"[^"]*"?|'[^']*'?)/, q, "\"'"]
		], [
			["tag", /^^<\/?[a-z](?:[\w-.:]*\w)?|\/?>$/i],
			["atn", /^(?!style[\s=]|on)[a-z](?:[\w:-]*\w)?/i],
			["lang-uq.val", /^=\s*([^\s"'>]*(?:[^\s"'/>]|\/(?=\s)))/],
			["pun", /^[/<->]+/],
			["lang-js", /^on\w+\s*=\s*"([^"]+)"/i],
			["lang-js", /^on\w+\s*=\s*'([^']+)'/i],
			["lang-js", /^on\w+\s*=\s*([^\s"'>]+)/i],
			["lang-css", /^style\s*=\s*"([^"]+)"/i],
			["lang-css", /^style\s*=\s*'([^']+)'/i],
			["lang-css", /^style\s*=\s*([^\s"'>]+)/i]
		]), ["in.tag"]);
		p(D([], [
			["atv", /^[\S\s]+/]
		]), ["uq.val"]);
		p(v(
		{
			keywords: M,
			hashComments: !0,
			cStyleComments: !0,
			types: Q
		}), ["c", "cc", "cpp", "cxx", "cyc", "m"]);
		p(v(
		{
			keywords: "null,true,false"
		}), ["json"]);
		p(v(
		{
			keywords: N,
			hashComments: !0,
			cStyleComments: !0,
			verbatimStrings: !0,
			types: Q
		}), ["cs"]);
		p(v(
		{
			keywords: V,
			cStyleComments: !0
		}), ["java"]);
		p(v(
		{
			keywords: y,
			hashComments: !0,
			multiLineStrings: !0
		}), ["bash", "bsh", "csh", "sh"]);
		p(v(
		{
			keywords: O,
			hashComments: !0,
			multiLineStrings: !0,
			tripleQuotedStrings: !0
		}), ["cv", "py", "python"]);
		p(v(
		{
			keywords: "caller,delete,die,do,dump,elsif,eval,exit,foreach,for,goto,if,import,last,local,my,next,no,our,print,package,redo,require,sub,undef,unless,until,use,wantarray,while,BEGIN,END",
			hashComments: !0,
			multiLineStrings: !0,
			regexLiterals: 2
		}), ["perl", "pl", "pm"]);
		p(v(
		{
			keywords: P,
			hashComments: !0,
			multiLineStrings: !0,
			regexLiterals: !0
		}), ["rb", "ruby"]);
		p(v(
		{
			keywords: C,
			cStyleComments: !0,
			regexLiterals: !0
		}), ["javascript", "js"]);
		p(v(
		{
			keywords: "all,and,by,catch,class,else,extends,false,finally,for,if,in,is,isnt,loop,new,no,not,null,of,off,on,or,return,super,then,throw,true,try,unless,until,when,while,yes",
			hashComments: 3,
			cStyleComments: !0,
			multilineStrings: !0,
			tripleQuotedStrings: !0,
			regexLiterals: !0
		}), ["coffee"]);
		p(v(
		{
			keywords: W,
			cStyleComments: !0,
			multilineStrings: !0
		}), ["rc", "rs", "rust"]);
		p(D([], [
			["str", /^[\S\s]+/]
		]), ["regex"]);
		var Y = E.PR = {
			createSimpleLexer: D,
			registerLangHandler: p,
			sourceDecorator: v,
			PR_ATTRIB_NAME: "atn",
			PR_ATTRIB_VALUE: "atv",
			PR_COMMENT: "com",
			PR_DECLARATION: "dec",
			PR_KEYWORD: "kwd",
			PR_LITERAL: "lit",
			PR_NOCODE: "nocode",
			PR_PLAIN: "pln",
			PR_PUNCTUATION: "pun",
			PR_SOURCE: "src",
			PR_STRING: "str",
			PR_TAG: "tag",
			PR_TYPE: "typ",
			prettyPrintOne: E.prettyPrintOne = function (a, d, g)
			{
				var b = document.createElement("div");
				b.innerHTML = "<pre>" + a + "</pre>";
				b = b.firstChild;
				g && J(b, g, !0);
				K(
				{
					h: d,
					j: g,
					c: b,
					i: 1
				});
				return b.innerHTML
			},
			prettyPrint: E.prettyPrint = function (a, d)
			{
				function g()
				{
					for (var b = E.PR_SHOULD_USE_CONTINUATION ? c.now() + 250 : Infinity; i < p.length && c.now() < b; i++)
					{
						for (var d = p[i], j = h, k = d; k = k.previousSibling;)
						{
							var m = k.nodeType,
								o = (m === 7 || m === 8) && k.nodeValue;
							if (o ? !/^\??prettify\b/.test(o) : m !== 3 || /\S/.test(k.nodeValue)) break;
							if (o)
							{
								j = {};
								o.replace(/\b(\w+)=([\w%+\-.:]+)/g, function (a, b, c)
								{
									j[b] = c
								});
								break
							}
						}
						k = d.className;
						if ((j !== h || e.test(k)) && !v.test(k))
						{
							m = !1;
							for (o = d.parentNode; o; o = o.parentNode)
								if (f.test(o.tagName) &&
									o.className && e.test(o.className))
								{
									m = !0;
									break
								}
							if (!m)
							{
								d.className += " prettyprinted";
								m = j.lang;
								if (!m)
								{
									var m = k.match(n),
										y;
									if (!m && (y = T(d)) && t.test(y.tagName)) m = y.className.match(n);
									m && (m = m[1])
								}
								if (w.test(d.tagName)) o = 1;
								else var o = d.currentStyle,
									u = s.defaultView,
									o = (o = o ? o.whiteSpace : u && u.getComputedStyle ? u.getComputedStyle(d, q).getPropertyValue("white-space") : 0) && "pre" === o.substring(0, 3);
								u = j.linenums;
								if (!(u = u === "true" || +u)) u = (u = k.match(/\blinenums\b(?::(\d+))?/)) ? u[1] && u[1].length ? +u[1] : !0 : !1;
								u && J(d, u, o);
								r = {
									h: m,
									c: d,
									j: u,
									i: o
								};
								K(r)
							}
						}
					}
					i < p.length ? setTimeout(g, 250) : "function" === typeof a && a()
				}
				for (var b = d || document.body, s = b.ownerDocument || document, b = [b.getElementsByTagName("pre"), b.getElementsByTagName("code"), b.getElementsByTagName("xmp")], p = [], m = 0; m < b.length; ++m)
					for (var j = 0, k = b[m].length; j < k; ++j)
						p.push(b[m][j]);
				var b = q,
					c = Date;
				c.now || (c = {
					now: function ()
					{
						return +new Date
					}
				});
				var i = 0,
					r, n = /\blang(?:uage)?-([\w.]+)(?!\S)/,
					e = /\bprettyprint\b/,
					v = /\bprettyprinted\b/,
					w = /pre|xmp/i,
					t = /^code$/i,
					f = /^(?:pre|code|xmp)$/i,
					h = {};
				g()
			}
		};
		typeof define === "function" && define.amd && define("google-code-prettify", [], function ()
		{
			return Y
		})
	})();
}()
DELIMITER";

string[string] extensions;

string lisp = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([["opn",/^\(+/,null,"("],["clo",/^\)+/,null,")"],[PR.PR_COMMENT,/^;[^\r\n]*/,null,";"],[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"    \n\r  "],[PR.PR_STRING,/^\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)/,null,'"']],[[PR.PR_KEYWORD,/^(?:block|c[ad]+r|catch|con[ds]|def(?:ine|un)|do|eq|eql|equal|equalp|eval-when|flet|format|go|if|labels|lambda|let|load-time-value|locally|macrolet|multiple-value-call|nil|progn|progv|quote|require|return-from|setq|symbol-macrolet|t|tagbody|the|throw|unwind)\b/,null],[PR.PR_LITERAL,/^[+\-]?(?:[0#]x[0-9a-f]+|\d+\/\d+|(?:\.\d+|\d+(?:\.\d*)?)(?:[ed][+\-]?\d+)?)/i],[PR.PR_LITERAL,/^\'(?:-*(?:\w|\\[\x21-\x7e])(?:[\w-]*|\\[\x21-\x7e])[=!?]?)?/],[PR.PR_PLAIN,/^-*(?:[a-z_]|\\[\x21-\x7e])(?:[\w-]*|\\[\x21-\x7e])[=!?]?/i],[PR.PR_PUNCTUATION,/^[^\w\t\n\r \xA0()\"\\\';]+/]]),["cl","el","lisp","lsp","scm","ss","rkt"]);
DELIMITER";
extensions["cl"] = lisp;
extensions["el"] = lisp;
extensions["lisp"] = lisp;
extensions["lsp"] = lisp;
extensions["scm"] = lisp;
extensions["ss"] = lisp;
extensions["rkt"] = lisp;
string clojure = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([["opn",/^[\(\{\[]+/,null,"([{"],["clo",/^[\)\}\]]+/,null,")]}"],[PR.PR_COMMENT,/^;[^\r\n]*/,null,";"],[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"    \n\r  "],[PR.PR_STRING,/^\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)/,null,'"']],[[PR.PR_KEYWORD,/^(?:def|if|do|let|quote|var|fn|loop|recur|throw|try|monitor-enter|monitor-exit|defmacro|defn|defn-|macroexpand|macroexpand-1|for|doseq|dosync|dotimes|and|or|when|not|assert|doto|proxy|defstruct|first|rest|cons|defprotocol|deftype|defrecord|reify|defmulti|defmethod|meta|with-meta|ns|in-ns|create-ns|import|intern|refer|alias|namespace|resolve|ref|deref|refset|new|set!|memfn|to-array|into-array|aset|gen-class|reduce|map|filter|find|nil?|empty?|hash-map|hash-set|vec|vector|seq|flatten|reverse|assoc|dissoc|list|list?|disj|get|union|difference|intersection|extend|extend-type|extend-protocol|prn)\b/,null],[PR.PR_TYPE,/^:[0-9a-zA-Z\-]+/]]),["clj"]);
DELIMITER";
extensions["clj"] = clojure;
string erlang = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\x0B\x0C\r ]+/,null,"  \n\f\r "],[PR.PR_STRING,/^\"(?:[^\"\\\n\x0C\r]|\\[\s\S])*(?:\"|$)/,null,'"'],[PR.PR_LITERAL,/^[a-z][a-zA-Z0-9_]*/],[PR.PR_LITERAL,/^\'(?:[^\'\\\n\x0C\r]|\\[^&])+\'?/,null,"'"],[PR.PR_LITERAL,/^\?[^ \t\n({]+/,null,"?"],[PR.PR_LITERAL,/^(?:0o[0-7]+|0x[\da-f]+|\d+(?:\.\d+)?(?:e[+\-]?\d+)?)/i,null,"0123456789"]],[[PR.PR_COMMENT,/^%[^\n]*/],[PR.PR_KEYWORD,/^(?:module|attributes|do|let|in|letrec|apply|call|primop|case|of|end|when|fun|try|catch|receive|after|char|integer|float,atom,string,var)\b/],[PR.PR_KEYWORD,/^-[a-z_]+/],[PR.PR_TYPE,/^[A-Z_][a-zA-Z0-9_]*/],[PR.PR_PUNCTUATION,/^[.,;]/]]),["erlang","erl"]);
DELIMITER";
extensions["erlang"] = erlang;
extensions["erl"] = erlang;
string go = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_PLAIN,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])+(?:\'|$)|`[^`]*(?:`|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^(?:\/\/[^\r\n]*|\/\*[\s\S]*?\*\/)/],[PR.PR_PLAIN,/^(?:[^\/\"\'`]|\/(?![\/\*]))+/i]]),["go"]);
DELIMITER";
extensions["go"] = go;
string rust = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([],[[PR.PR_PLAIN,/^[\t\n\r \xA0]+/],[PR.PR_COMMENT,/^\/\/.*/],[PR.PR_COMMENT,/^\/\*[\s\S]*?(?:\*\/|$)/],[PR.PR_STRING,/^b"(?:[^\\]|\\(?:.|x[\da-fA-F]{2}))*?"/],[PR.PR_STRING,/^"(?:[^\\]|\\(?:.|x[\da-fA-F]{2}|u\{\[\da-fA-F]{1,6}\}))*?"/],[PR.PR_STRING,/^b?r(#*)\"[\s\S]*?\"\1/],[PR.PR_STRING,/^b'([^\\]|\\(.|x[\da-fA-F]{2}))'/],[PR.PR_STRING,/^'([^\\]|\\(.|x[\da-fA-F]{2}|u\{[\da-fA-F]{1,6}\}))'/],[PR.PR_TAG,/^'\w+?\b/],[PR.PR_KEYWORD,/^(?:match|if|else|as|break|box|continue|extern|fn|for|in|if|impl|let|loop|pub|return|super|unsafe|where|while|use|mod|trait|struct|enum|type|move|mut|ref|static|const|crate)\b/],[PR.PR_KEYWORD,/^(?:alignof|become|do|offsetof|priv|pure|sizeof|typeof|unsized|yield|abstract|virtual|final|override|macro)\b/],[PR.PR_TYPE,/^(?:[iu](8|16|32|64|size)|char|bool|f32|f64|str|Self)\b/],[PR.PR_TYPE,/^(?:Copy|Send|Sized|Sync|Drop|Fn|FnMut|FnOnce|Box|ToOwned|Clone|PartialEq|PartialOrd|Eq|Ord|AsRef|AsMut|Into|From|Default|Iterator|Extend|IntoIterator|DoubleEndedIterator|ExactSizeIterator|Option|Some|None|Result|Ok|Err|SliceConcatExt|String|ToString|Vec)\b/],[PR.PR_LITERAL,/^(self|true|false|null)\b/],[PR.PR_LITERAL,/^\d[0-9_]*(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0x[a-fA-F0-9_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0o[0-7_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^0b[01_]+(?:[iu](?:size|8|16|32|64))?/],[PR.PR_LITERAL,/^\d[0-9_]*\.(?![^\s\d.])/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)(?:[eE][+-]?[0-9_]+)?(?:f32|f64)?/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)?(?:[eE][+-]?[0-9_]+)(?:f32|f64)?/],[PR.PR_LITERAL,/^\d[0-9_]*(?:\.\d[0-9_]*)?(?:[eE][+-]?[0-9_]+)?(?:f32|f64)/],[PR.PR_ATTRIB_NAME,/^[a-z_]\w*!/i],[PR.PR_PLAIN,/^[a-z_]\w*/i],[PR.PR_ATTRIB_VALUE,/^#!?\[[\s\S]*?\]/],[PR.PR_PUNCTUATION,/^[+\-\/*=^&|!<>%[\](){}?:.,;]/],[PR.PR_PLAIN,/./]]),["rs"]);
DELIMITER";
extensions["rs"] = rust;
string swift = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[ \n\r\t\v\f\0]+/,null," \n\r   \f\x00"],[PR.PR_STRING,/^"(?:[^"\\]|(?:\\.)|(?:\\\((?:[^"\\)]|\\.)*\)))*"/,null,'"']],[[PR.PR_LITERAL,/^(?:(?:0x[\da-fA-F][\da-fA-F_]*\.[\da-fA-F][\da-fA-F_]*[pP]?)|(?:\d[\d_]*\.\d[\d_]*[eE]?))[+-]?\d[\d_]*/,null],[PR.PR_LITERAL,/^-?(?:(?:0(?:(?:b[01][01_]*)|(?:o[0-7][0-7_]*)|(?:x[\da-fA-F][\da-fA-F_]*)))|(?:\d[\d_]*))/,null],[PR.PR_LITERAL,/^(?:true|false|nil)\b/,null],[PR.PR_KEYWORD,/^\b(?:__COLUMN__|__FILE__|__FUNCTION__|__LINE__|#available|#else|#elseif|#endif|#if|#line|arch|arm|arm64|associativity|as|break|case|catch|class|continue|convenience|default|defer|deinit|didSet|do|dynamic|dynamicType|else|enum|extension|fallthrough|final|for|func|get|guard|import|indirect|infix|init|inout|internal|i386|if|in|iOS|iOSApplicationExtension|is|lazy|left|let|mutating|none|nonmutating|operator|optional|OSX|OSXApplicationExtension|override|postfix|precedence|prefix|private|protocol|Protocol|public|required|rethrows|return|right|safe|self|set|static|struct|subscript|super|switch|throw|try|Type|typealias|unowned|unsafe|var|weak|watchOS|while|willSet|x86_64)\b/,null],[PR.PR_COMMENT,/^\/\/.*?[\n\r]/,null],[PR.PR_COMMENT,/^\/\*[\s\S]*?(?:\*\/|$)/,null],[PR.PR_PUNCTUATION,/^<<=|<=|<<|>>=|>=|>>|===|==|\.\.\.|&&=|\.\.<|!==|!=|&=|~=|~|\(|\)|\[|\]|{|}|@|#|;|\.|,|:|\|\|=|\?\?|\|\||&&|&\*|&\+|&-|&=|\+=|-=|\/=|\*=|\^=|%=|\|=|->|`|==|\+\+|--|\/|\+|!|\*|%|<|>|&|\||\^|\?|=|-|_/,null],[PR.PR_TYPE,/^\b(?:[@_]?[A-Z]+[a-z][A-Za-z_$@0-9]*|\w+_t\b)/,null]]),["swift"]);
DELIMITER";
extensions["swift"] = swift;
string haskell = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\x0B\x0C\r ]+/,null,"  \n\f\r "],[PR.PR_STRING,/^\"(?:[^\"\\\n\x0C\r]|\\[\s\S])*(?:\"|$)/,null,'"'],[PR.PR_STRING,/^\'(?:[^\'\\\n\x0C\r]|\\[^&])\'?/,null,"'"],[PR.PR_LITERAL,/^(?:0o[0-7]+|0x[\da-f]+|\d+(?:\.\d+)?(?:e[+\-]?\d+)?)/i,null,"0123456789"]],[[PR.PR_COMMENT,/^(?:(?:--+(?:[^\r\n\x0C]*)?)|(?:\{-(?:[^-]|-+[^-\}])*-\}))/],[PR.PR_KEYWORD,/^(?:case|class|data|default|deriving|do|else|if|import|in|infix|infixl|infixr|instance|let|module|newtype|of|then|type|where|_)(?=[^a-zA-Z0-9\']|$)/,null],[PR.PR_PLAIN,/^(?:[A-Z][\w\']*\.)*[a-zA-Z][\w\']*/],[PR.PR_PUNCTUATION,/^[^\t\n\x0B\x0C\r a-zA-Z0-9\'\"]+/]]),["hs"]);
DELIMITER";
extensions["hs"] = haskell;
string matlab = q"DELIMITER
(function (PR) {
  /*
    PR_PLAIN: plain text
    PR_STRING: string literals
    PR_KEYWORD: keywords
    PR_COMMENT: comments
    PR_TYPE: types
    PR_LITERAL: literal values (1, null, true, ..)
    PR_PUNCTUATION: punctuation string
    PR_SOURCE: embedded source
    PR_DECLARATION: markup declaration such as a DOCTYPE
    PR_TAG: sgml tag
    PR_ATTRIB_NAME: sgml attribute name
    PR_ATTRIB_VALUE: sgml attribute value
  */
  var PR_IDENTIFIER = "ident",
    PR_CONSTANT = "const",
    PR_FUNCTION = "fun",
    PR_FUNCTION_TOOLBOX = "fun_tbx",
    PR_SYSCMD = "syscmd",
    PR_CODE_OUTPUT = "codeoutput",
    PR_ERROR = "err",
    PR_WARNING = "wrn",
    PR_TRANSPOSE = "transpose",
    PR_LINE_CONTINUATION = "linecont";

  // Refer to: https://www.mathworks.com/help/matlab/functionlist-alpha.html
  var coreFunctions = [
    'abs|accumarray|acos(?:d|h)?|acot(?:d|h)?|acsc(?:d|h)?|actxcontrol(?:list|select)?|actxGetRunningServer|actxserver|addlistener|addpath|addpref|addtodate|airy|align|alim|all|allchild|alpha|alphamap|amd|ancestor|and|angle|annotation|any|area|arrayfun|asec(?:d|h)?|asin(?:d|h)?|assert|assignin|atan(?:2|d|h)?|audiodevinfo|audioplayer|audiorecorder|aufinfo|auread|autumn|auwrite|avifile|aviinfo|aviread|axes|axis|balance|bar(?:3|3h|h)?|base2dec|beep|BeginInvoke|bench|bessel(?:h|i|j|k|y)|beta|betainc|betaincinv|betaln|bicg|bicgstab|bicgstabl|bin2dec|bitand|bitcmp|bitget|bitmax|bitnot|bitor|bitset|bitshift|bitxor|blanks|blkdiag|bone|box|brighten|brush|bsxfun|builddocsearchdb|builtin|bvp4c|bvp5c|bvpget|bvpinit|bvpset|bvpxtend|calendar|calllib|callSoapService|camdolly|cameratoolbar|camlight|camlookat|camorbit|campan|campos|camproj|camroll|camtarget|camup|camva|camzoom|cart2pol|cart2sph|cast|cat|caxis|cd|cdf2rdf|cdfepoch|cdfinfo|cdflib(?:\.(?:close|closeVar|computeEpoch|computeEpoch16|create|createAttr|createVar|delete|deleteAttr|deleteAttrEntry|deleteAttrgEntry|deleteVar|deleteVarRecords|epoch16Breakdown|epochBreakdown|getAttrEntry|getAttrgEntry|getAttrMaxEntry|getAttrMaxgEntry|getAttrName|getAttrNum|getAttrScope|getCacheSize|getChecksum|getCompression|getCompressionCacheSize|getConstantNames|getConstantValue|getCopyright|getFileBackward|getFormat|getLibraryCopyright|getLibraryVersion|getMajority|getName|getNumAttrEntries|getNumAttrgEntries|getNumAttributes|getNumgAttributes|getReadOnlyMode|getStageCacheSize|getValidate|getVarAllocRecords|getVarBlockingFactor|getVarCacheSize|getVarCompression|getVarData|getVarMaxAllocRecNum|getVarMaxWrittenRecNum|getVarName|getVarNum|getVarNumRecsWritten|getVarPadValue|getVarRecordData|getVarReservePercent|getVarsMaxWrittenRecNum|getVarSparseRecords|getVersion|hyperGetVarData|hyperPutVarData|inquire|inquireAttr|inquireAttrEntry|inquireAttrgEntry|inquireVar|open|putAttrEntry|putAttrgEntry|putVarData|putVarRecordData|renameAttr|renameVar|setCacheSize|setChecksum|setCompression|setCompressionCacheSize|setFileBackward|setFormat|setMajority|setReadOnlyMode|setStageCacheSize|setValidate|setVarAllocBlockRecords|setVarBlockingFactor|setVarCacheSize|setVarCompression|setVarInitialRecs|setVarPadValue|SetVarReservePercent|setVarsCacheSize|setVarSparseRecords))?|cdfread|cdfwrite|ceil|cell2mat|cell2struct|celldisp|cellfun|cellplot|cellstr|cgs|checkcode|checkin|checkout|chol|cholinc|cholupdate|circshift|cla|clabel|class|clc|clear|clearvars|clf|clipboard|clock|close|closereq|cmopts|cmpermute|cmunique|colamd|colon|colorbar|colordef|colormap|colormapeditor|colperm|Combine|comet|comet3|commandhistory|commandwindow|compan|compass|complex|computer|cond|condeig|condest|coneplot|conj|containers\.Map|contour(?:3|c|f|slice)?|contrast|conv|conv2|convhull|convhulln|convn|cool|copper|copyfile|copyobj|corrcoef|cos(?:d|h)?|cot(?:d|h)?|cov|cplxpair|cputime|createClassFromWsdl|createSoapMessage|cross|csc(?:d|h)?|csvread|csvwrite|ctranspose|cumprod|cumsum|cumtrapz|curl|customverctrl|cylinder|daqread|daspect|datacursormode|datatipinfo|date|datenum|datestr|datetick|datevec|dbclear|dbcont|dbdown|dblquad|dbmex|dbquit|dbstack|dbstatus|dbstep|dbstop|dbtype|dbup|dde23|ddeget|ddesd|ddeset|deal|deblank|dec2base|dec2bin|dec2hex|decic|deconv|del2|delaunay|delaunay3|delaunayn|DelaunayTri|delete|demo|depdir|depfun|det|detrend|deval|diag|dialog|diary|diff|diffuse|dir|disp|display|dither|divergence|dlmread|dlmwrite|dmperm|doc|docsearch|dos|dot|dragrect|drawnow|dsearch|dsearchn|dynamicprops|echo|echodemo|edit|eig|eigs|ellipj|ellipke|ellipsoid|empty|enableNETfromNetworkDrive|enableservice|EndInvoke|enumeration|eomday|eq|erf|erfc|erfcinv|erfcx|erfinv|error|errorbar|errordlg|etime|etree|etreeplot|eval|evalc|evalin|event\.(?:EventData|listener|PropertyEvent|proplistener)|exifread|exist|exit|exp|expint|expm|expm1|export2wsdlg|eye|ezcontour|ezcontourf|ezmesh|ezmeshc|ezplot|ezplot3|ezpolar|ezsurf|ezsurfc|factor|factorial|fclose|feather|feature|feof|ferror|feval|fft|fft2|fftn|fftshift|fftw|fgetl|fgets|fieldnames|figure|figurepalette|fileattrib|filebrowser|filemarker|fileparts|fileread|filesep|fill|fill3|filter|filter2|find|findall|findfigs|findobj|findstr|finish|fitsdisp|fitsinfo|fitsread|fitswrite|fix|flag|flipdim|fliplr|flipud|floor|flow|fminbnd|fminsearch|fopen|format|fplot|fprintf|frame2im|fread|freqspace|frewind|fscanf|fseek|ftell|FTP|full|fullfile|func2str|functions|funm|fwrite|fzero|gallery|gamma|gammainc|gammaincinv|gammaln|gca|gcbf|gcbo|gcd|gcf|gco|ge|genpath|genvarname|get|getappdata|getenv|getfield|getframe|getpixelposition|getpref|ginput|gmres|gplot|grabcode|gradient|gray|graymon|grid|griddata(?:3|n)?|griddedInterpolant|gsvd|gt|gtext|guidata|guide|guihandles|gunzip|gzip|h5create|h5disp|h5info|h5read|h5readatt|h5write|h5writeatt|hadamard|handle|hankel|hdf|hdf5|hdf5info|hdf5read|hdf5write|hdfinfo|hdfread|hdftool|help|helpbrowser|helpdesk|helpdlg|helpwin|hess|hex2dec|hex2num|hgexport|hggroup|hgload|hgsave|hgsetget|hgtransform|hidden|hilb|hist|histc|hold|home|horzcat|hostid|hot|hsv|hsv2rgb|hypot|ichol|idivide|ifft|ifft2|ifftn|ifftshift|ilu|im2frame|im2java|imag|image|imagesc|imapprox|imfinfo|imformats|import|importdata|imread|imwrite|ind2rgb|ind2sub|inferiorto|info|inline|inmem|inpolygon|input|inputdlg|inputname|inputParser|inspect|instrcallback|instrfind|instrfindall|int2str|integral(?:2|3)?|interp(?:1|1q|2|3|ft|n)|interpstreamspeed|intersect|intmax|intmin|inv|invhilb|ipermute|isa|isappdata|iscell|iscellstr|ischar|iscolumn|isdir|isempty|isequal|isequaln|isequalwithequalnans|isfield|isfinite|isfloat|isglobal|ishandle|ishghandle|ishold|isinf|isinteger|isjava|iskeyword|isletter|islogical|ismac|ismatrix|ismember|ismethod|isnan|isnumeric|isobject|isocaps|isocolors|isonormals|isosurface|ispc|ispref|isprime|isprop|isreal|isrow|isscalar|issorted|isspace|issparse|isstr|isstrprop|isstruct|isstudent|isunix|isvarname|isvector|javaaddpath|javaArray|javachk|javaclasspath|javacomponent|javaMethod|javaMethodEDT|javaObject|javaObjectEDT|javarmpath|jet|keyboard|kron|lasterr|lasterror|lastwarn|lcm|ldivide|ldl|le|legend|legendre|length|libfunctions|libfunctionsview|libisloaded|libpointer|libstruct|license|light|lightangle|lighting|lin2mu|line|lines|linkaxes|linkdata|linkprop|linsolve|linspace|listdlg|listfonts|load|loadlibrary|loadobj|log|log10|log1p|log2|loglog|logm|logspace|lookfor|lower|ls|lscov|lsqnonneg|lsqr|lt|lu|luinc|magic|makehgtform|mat2cell|mat2str|material|matfile|matlab\.io\.MatFile|matlab\.mixin\.(?:Copyable|Heterogeneous(?:\.getDefaultScalarElement)?)|matlabrc|matlabroot|max|maxNumCompThreads|mean|median|membrane|memmapfile|memory|menu|mesh|meshc|meshgrid|meshz|meta\.(?:class(?:\.fromName)?|DynamicProperty|EnumeratedValue|event|MetaData|method|package(?:\.(?:fromName|getAllPackages))?|property)|metaclass|methods|methodsview|mex(?:\.getCompilerConfigurations)?|MException|mexext|mfilename|min|minres|minus|mislocked|mkdir|mkpp|mldivide|mlint|mlintrpt|mlock|mmfileinfo|mmreader|mod|mode|more|move|movefile|movegui|movie|movie2avi|mpower|mrdivide|msgbox|mtimes|mu2lin|multibandread|multibandwrite|munlock|namelengthmax|nargchk|narginchk|nargoutchk|native2unicode|nccreate|ncdisp|nchoosek|ncinfo|ncread|ncreadatt|ncwrite|ncwriteatt|ncwriteschema|ndgrid|ndims|ne|NET(?:\.(?:addAssembly|Assembly|convertArray|createArray|createGeneric|disableAutoRelease|enableAutoRelease|GenericClass|invokeGenericMethod|NetException|setStaticProperty))?|netcdf\.(?:abort|close|copyAtt|create|defDim|defGrp|defVar|defVarChunking|defVarDeflate|defVarFill|defVarFletcher32|delAtt|endDef|getAtt|getChunkCache|getConstant|getConstantNames|getVar|inq|inqAtt|inqAttID|inqAttName|inqDim|inqDimID|inqDimIDs|inqFormat|inqGrpName|inqGrpNameFull|inqGrpParent|inqGrps|inqLibVers|inqNcid|inqUnlimDims|inqVar|inqVarChunking|inqVarDeflate|inqVarFill|inqVarFletcher32|inqVarID|inqVarIDs|open|putAtt|putVar|reDef|renameAtt|renameDim|renameVar|setChunkCache|setDefaultFormat|setFill|sync)|newplot|nextpow2|nnz|noanimate|nonzeros|norm|normest|not|notebook|now|nthroot|null|num2cell|num2hex|num2str|numel|nzmax|ode(?:113|15i|15s|23|23s|23t|23tb|45)|odeget|odeset|odextend|onCleanup|ones|open|openfig|opengl|openvar|optimget|optimset|or|ordeig|orderfields|ordqz|ordschur|orient|orth|pack|padecoef|pagesetupdlg|pan|pareto|parseSoapResponse|pascal|patch|path|path2rc|pathsep|pathtool|pause|pbaspect|pcg|pchip|pcode|pcolor|pdepe|pdeval|peaks|perl|perms|permute|pie|pink|pinv|planerot|playshow|plot|plot3|plotbrowser|plotedit|plotmatrix|plottools|plotyy|plus|pol2cart|polar|poly|polyarea|polyder|polyeig|polyfit|polyint|polyval|polyvalm|pow2|power|ppval|prefdir|preferences|primes|print|printdlg|printopt|printpreview|prod|profile|profsave|propedit|propertyeditor|psi|publish|PutCharArray|PutFullMatrix|PutWorkspaceData|pwd|qhull|qmr|qr|qrdelete|qrinsert|qrupdate|quad|quad2d|quadgk|quadl|quadv|questdlg|quit|quiver|quiver3|qz|rand|randi|randn|randperm|RandStream(?:\.(?:create|getDefaultStream|getGlobalStream|list|setDefaultStream|setGlobalStream))?|rank|rat|rats|rbbox|rcond|rdivide|readasync|real|reallog|realmax|realmin|realpow|realsqrt|record|rectangle|rectint|recycle|reducepatch|reducevolume|refresh|refreshdata|regexp|regexpi|regexprep|regexptranslate|rehash|rem|Remove|RemoveAll|repmat|reset|reshape|residue|restoredefaultpath|rethrow|rgb2hsv|rgb2ind|rgbplot|ribbon|rmappdata|rmdir|rmfield|rmpath|rmpref|rng|roots|rose|rosser|rot90|rotate|rotate3d|round|rref|rsf2csf|run|save|saveas|saveobj|savepath|scatter|scatter3|schur|sec|secd|sech|selectmoveresize|semilogx|semilogy|sendmail|serial|set|setappdata|setdiff|setenv|setfield|setpixelposition|setpref|setstr|setxor|shading|shg|shiftdim|showplottool|shrinkfaces|sign|sin(?:d|h)?|size|slice|smooth3|snapnow|sort|sortrows|sound|soundsc|spalloc|spaugment|spconvert|spdiags|specular|speye|spfun|sph2cart|sphere|spinmap|spline|spones|spparms|sprand|sprandn|sprandsym|sprank|spring|sprintf|spy|sqrt|sqrtm|squeeze|ss2tf|sscanf|stairs|startup|std|stem|stem3|stopasync|str2double|str2func|str2mat|str2num|strcat|strcmp|strcmpi|stream2|stream3|streamline|streamparticles|streamribbon|streamslice|streamtube|strfind|strjust|strmatch|strncmp|strncmpi|strread|strrep|strtok|strtrim|struct2cell|structfun|strvcat|sub2ind|subplot|subsasgn|subsindex|subspace|subsref|substruct|subvolume|sum|summer|superclasses|superiorto|support|surf|surf2patch|surface|surfc|surfl|surfnorm|svd|svds|swapbytes|symamd|symbfact|symmlq|symrcm|symvar|system|tan(?:d|h)?|tar|tempdir|tempname|tetramesh|texlabel|text|textread|textscan|textwrap|tfqmr|throw|tic|Tiff(?:\.(?:getTagNames|getVersion))?|timer|timerfind|timerfindall|times|timeseries|title|toc|todatenum|toeplitz|toolboxdir|trace|transpose|trapz|treelayout|treeplot|tril|trimesh|triplequad|triplot|TriRep|TriScatteredInterp|trisurf|triu|tscollection|tsearch|tsearchn|tstool|type|typecast|uibuttongroup|uicontextmenu|uicontrol|uigetdir|uigetfile|uigetpref|uiimport|uimenu|uiopen|uipanel|uipushtool|uiputfile|uiresume|uisave|uisetcolor|uisetfont|uisetpref|uistack|uitable|uitoggletool|uitoolbar|uiwait|uminus|undocheckout|unicode2native|union|unique|unix|unloadlibrary|unmesh|unmkpp|untar|unwrap|unzip|uplus|upper|urlread|urlwrite|usejava|userpath|validateattributes|validatestring|vander|var|vectorize|ver|verctrl|verLessThan|version|vertcat|VideoReader(?:\.isPlatformSupported)?|VideoWriter(?:\.getProfiles)?|view|viewmtx|visdiff|volumebounds|voronoi|voronoin|wait|waitbar|waitfor|waitforbuttonpress|warndlg|warning|waterfall|wavfinfo|wavplay|wavread|wavrecord|wavwrite|web|weekday|what|whatsnew|which|whitebg|who|whos|wilkinson|winopen|winqueryreg|winter|wk1finfo|wk1read|wk1write|workspace|xlabel|xlim|xlsfinfo|xlsread|xlswrite|xmlread|xmlwrite|xor|xslt|ylabel|ylim|zeros|zip|zlabel|zlim|zoom'
  ].join("|");
  var statsFunctions = [
    'addedvarplot|andrewsplot|anova(?:1|2|n)|ansaribradley|aoctool|barttest|bbdesign|beta(?:cdf|fit|inv|like|pdf|rnd|stat)|bino(?:cdf|fit|inv|pdf|rnd|stat)|biplot|bootci|bootstrp|boxplot|candexch|candgen|canoncorr|capability|capaplot|caseread|casewrite|categorical|ccdesign|cdfplot|chi2(?:cdf|gof|inv|pdf|rnd|stat)|cholcov|Classification(?:BaggedEnsemble|Discriminant(?:\.(?:fit|make|template))?|Ensemble|KNN(?:\.(?:fit|template))?|PartitionedEnsemble|PartitionedModel|Tree(?:\.(?:fit|template))?)|classify|classregtree|cluster|clusterdata|cmdscale|combnk|Compact(?:Classification(?:Discriminant|Ensemble|Tree)|Regression(?:Ensemble|Tree)|TreeBagger)|confusionmat|controlchart|controlrules|cophenet|copula(?:cdf|fit|param|pdf|rnd|stat)|cordexch|corr|corrcov|coxphfit|createns|crosstab|crossval|cvpartition|datasample|dataset|daugment|dcovary|dendrogram|dfittool|disttool|dummyvar|dwtest|ecdf|ecdfhist|ev(?:cdf|fit|inv|like|pdf|rnd|stat)|ExhaustiveSearcher|exp(?:cdf|fit|inv|like|pdf|rnd|stat)|factoran|fcdf|ff2n|finv|fitdist|fitensemble|fpdf|fracfact|fracfactgen|friedman|frnd|fstat|fsurfht|fullfact|gagerr|gam(?:cdf|fit|inv|like|pdf|rnd|stat)|GeneralizedLinearModel(?:\.fit)?|geo(?:cdf|inv|mean|pdf|rnd|stat)|gev(?:cdf|fit|inv|like|pdf|rnd|stat)|gline|glmfit|glmval|glyphplot|gmdistribution(?:\.fit)?|gname|gp(?:cdf|fit|inv|like|pdf|rnd|stat)|gplotmatrix|grp2idx|grpstats|gscatter|haltonset|harmmean|hist3|histfit|hmm(?:decode|estimate|generate|train|viterbi)|hougen|hyge(?:cdf|inv|pdf|rnd|stat)|icdf|inconsistent|interactionplot|invpred|iqr|iwishrnd|jackknife|jbtest|johnsrnd|KDTreeSearcher|kmeans|knnsearch|kruskalwallis|ksdensity|kstest|kstest2|kurtosis|lasso|lassoglm|lassoPlot|leverage|lhsdesign|lhsnorm|lillietest|LinearModel(?:\.fit)?|linhyptest|linkage|logn(?:cdf|fit|inv|like|pdf|rnd|stat)|lsline|mad|mahal|maineffectsplot|manova1|manovacluster|mdscale|mhsample|mle|mlecov|mnpdf|mnrfit|mnrnd|mnrval|moment|multcompare|multivarichart|mvn(?:cdf|pdf|rnd)|mvregress|mvregresslike|mvt(?:cdf|pdf|rnd)|NaiveBayes(?:\.fit)?|nan(?:cov|max|mean|median|min|std|sum|var)|nbin(?:cdf|fit|inv|pdf|rnd|stat)|ncf(?:cdf|inv|pdf|rnd|stat)|nct(?:cdf|inv|pdf|rnd|stat)|ncx2(?:cdf|inv|pdf|rnd|stat)|NeighborSearcher|nlinfit|nlintool|nlmefit|nlmefitsa|nlparci|nlpredci|nnmf|nominal|NonLinearModel(?:\.fit)?|norm(?:cdf|fit|inv|like|pdf|rnd|stat)|normplot|normspec|ordinal|outlierMeasure|parallelcoords|paretotails|partialcorr|pcacov|pcares|pdf|pdist|pdist2|pearsrnd|perfcurve|perms|piecewisedistribution|plsregress|poiss(?:cdf|fit|inv|pdf|rnd|tat)|polyconf|polytool|prctile|princomp|ProbDist(?:Kernel|Parametric|UnivKernel|UnivParam)?|probplot|procrustes|qqplot|qrandset|qrandstream|quantile|randg|random|randsample|randtool|range|rangesearch|ranksum|rayl(?:cdf|fit|inv|pdf|rnd|stat)|rcoplot|refcurve|refline|regress|Regression(?:BaggedEnsemble|Ensemble|PartitionedEnsemble|PartitionedModel|Tree(?:\.(?:fit|template))?)|regstats|relieff|ridge|robustdemo|robustfit|rotatefactors|rowexch|rsmdemo|rstool|runstest|sampsizepwr|scatterhist|sequentialfs|signrank|signtest|silhouette|skewness|slicesample|sobolset|squareform|statget|statset|stepwise|stepwisefit|surfht|tabulate|tblread|tblwrite|tcdf|tdfread|tiedrank|tinv|tpdf|TreeBagger|treedisp|treefit|treeprune|treetest|treeval|trimmean|trnd|tstat|ttest|ttest2|unid(?:cdf|inv|pdf|rnd|stat)|unif(?:cdf|inv|it|pdf|rnd|stat)|vartest(?:2|n)?|wbl(?:cdf|fit|inv|like|pdf|rnd|stat)|wblplot|wishrnd|x2fx|xptread|zscore|ztest'
  ].join("|");
  var imageFunctions = [
    'adapthisteq|analyze75info|analyze75read|applycform|applylut|axes2pix|bestblk|blockproc|bwarea|bwareaopen|bwboundaries|bwconncomp|bwconvhull|bwdist|bwdistgeodesic|bweuler|bwhitmiss|bwlabel|bwlabeln|bwmorph|bwpack|bwperim|bwselect|bwtraceboundary|bwulterode|bwunpack|checkerboard|col2im|colfilt|conndef|convmtx2|corner|cornermetric|corr2|cp2tform|cpcorr|cpselect|cpstruct2pairs|dct2|dctmtx|deconvblind|deconvlucy|deconvreg|deconvwnr|decorrstretch|demosaic|dicom(?:anon|dict|info|lookup|read|uid|write)|edge|edgetaper|entropy|entropyfilt|fan2para|fanbeam|findbounds|fliptform|freqz2|fsamp2|fspecial|ftrans2|fwind1|fwind2|getheight|getimage|getimagemodel|getline|getneighbors|getnhood|getpts|getrangefromclass|getrect|getsequence|gray2ind|graycomatrix|graycoprops|graydist|grayslice|graythresh|hdrread|hdrwrite|histeq|hough|houghlines|houghpeaks|iccfind|iccread|iccroot|iccwrite|idct2|ifanbeam|im2bw|im2col|im2double|im2int16|im2java2d|im2single|im2uint16|im2uint8|imabsdiff|imadd|imadjust|ImageAdapter|imageinfo|imagemodel|imapplymatrix|imattributes|imbothat|imclearborder|imclose|imcolormaptool|imcomplement|imcontour|imcontrast|imcrop|imdilate|imdisplayrange|imdistline|imdivide|imellipse|imerode|imextendedmax|imextendedmin|imfill|imfilter|imfindcircles|imfreehand|imfuse|imgca|imgcf|imgetfile|imhandles|imhist|imhmax|imhmin|imimposemin|imlincomb|imline|immagbox|immovie|immultiply|imnoise|imopen|imoverview|imoverviewpanel|impixel|impixelinfo|impixelinfoval|impixelregion|impixelregionpanel|implay|impoint|impoly|impositionrect|improfile|imputfile|impyramid|imreconstruct|imrect|imregconfig|imregionalmax|imregionalmin|imregister|imresize|imroi|imrotate|imsave|imscrollpanel|imshow|imshowpair|imsubtract|imtool|imtophat|imtransform|imview|ind2gray|ind2rgb|interfileinfo|interfileread|intlut|ippl|iptaddcallback|iptcheckconn|iptcheckhandle|iptcheckinput|iptcheckmap|iptchecknargin|iptcheckstrs|iptdemos|iptgetapi|iptGetPointerBehavior|iptgetpref|ipticondir|iptnum2ordinal|iptPointerManager|iptprefs|iptremovecallback|iptSetPointerBehavior|iptsetpref|iptwindowalign|iradon|isbw|isflat|isgray|isicc|isind|isnitf|isrgb|isrset|lab2double|lab2uint16|lab2uint8|label2rgb|labelmatrix|makecform|makeConstrainToRectFcn|makehdr|makelut|makeresampler|maketform|mat2gray|mean2|medfilt2|montage|nitfinfo|nitfread|nlfilter|normxcorr2|ntsc2rgb|openrset|ordfilt2|otf2psf|padarray|para2fan|phantom|poly2mask|psf2otf|qtdecomp|qtgetblk|qtsetblk|radon|rangefilt|reflect|regionprops|registration\.metric\.(?:MattesMutualInformation|MeanSquares)|registration\.optimizer\.(?:OnePlusOneEvolutionary|RegularStepGradientDescent)|rgb2gray|rgb2ntsc|rgb2ycbcr|roicolor|roifill|roifilt2|roipoly|rsetwrite|std2|stdfilt|strel|stretchlim|subimage|tformarray|tformfwd|tforminv|tonemap|translate|truesize|uintlut|viscircles|warp|watershed|whitepoint|wiener2|xyz2double|xyz2uint16|ycbcr2rgb'
  ].join("|");
  var optimFunctions = [
    'bintprog|color|fgoalattain|fminbnd|fmincon|fminimax|fminsearch|fminunc|fseminf|fsolve|fzero|fzmult|gangstr|ktrlink|linprog|lsqcurvefit|lsqlin|lsqnonlin|lsqnonneg|optimget|optimset|optimtool|quadprog'
  ].join("|");

  // identifiers: variable/function name, or a chain of variable names joined by dots (obj.method, struct.field1.field2, etc..)
  // valid variable names (start with letter, and contains letters, digits, and underscores).
  // we match "xx.yy" as a whole so that if "xx" is plain and "yy" is not, we dont get a false positive for "yy"
  //var reIdent = '(?:[a-zA-Z][a-zA-Z0-9_]*)';
  //var reIdentChain = '(?:' + reIdent + '(?:\.' + reIdent + ')*' + ')';

  // patterns that always start with a known character. Must have a shortcut string.
  var shortcutStylePatterns = [
    // whitespaces: space, tab, carriage return, line feed, line tab, form-feed, non-break space
    [PR.PR_PLAIN, /^[ \t\r\n\v\f\xA0]+/, null, " \t\r\n\u000b\u000c\u00a0"],

    // block comments
    //TODO: chokes on nested block comments
    //TODO: false positives when the lines with %{ and %} contain non-spaces
    //[PR.PR_COMMENT, /^%(?:[^\{].*|\{(?:%|%*[^\}%])*(?:\}+%?)?)/, null],
    [PR.PR_COMMENT, /^%\{[^%]*%+(?:[^\}%][^%]*%+)*\}/, null],

    // single-line comments
    [PR.PR_COMMENT, /^%[^\r\n]*/, null, "%"],

    // system commands
    [PR_SYSCMD, /^![^\r\n]*/, null, "!"]
  ];

  // patterns that will be tried in order if the shortcut ones fail. May have shortcuts.
  var fallthroughStylePatterns = [
    // line continuation
    [PR_LINE_CONTINUATION, /^\.\.\.\s*[\r\n]/, null],

    // error message
    [PR_ERROR, /^\?\?\? [^\r\n]*/, null],

    // warning message
    [PR_WARNING, /^Warning: [^\r\n]*/, null],

    // command prompt/output
    //[PR_CODE_OUTPUT, /^>>\s+[^\r\n]*[\r\n]{1,2}[^=]*=[^\r\n]*[\r\n]{1,2}[^\r\n]*/, null],    // full command output (both loose/compact format): `>> EXP\nVAR =\n VAL`
    [PR_CODE_OUTPUT, /^>>\s+/, null],      // only the command prompt `>> `
    [PR_CODE_OUTPUT, /^octave:\d+>\s+/, null],  // Octave command prompt `octave:1> `

    // identifier (chain) or closing-parenthesis/brace/bracket, and IS followed by transpose operator
    // this way we dont misdetect the transpose operator ' as the start of a string
    ["lang-matlab-operators", /^((?:[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*|\)|\]|\}|\.)')/, null],

    // single-quoted strings: allow for escaping with '', no multilines
    //[PR.PR_STRING, /(?:(?<=(?:\(|\[|\{|\s|=|;|,|:))|^)'(?:[^']|'')*'(?=(?:\)|\]|\}|\s|=|;|,|:|~|<|>|&|-|\+|\*|\.|\^|\|))/, null],  // string vs. transpose (check before/after context using negative/positive lookbehind/lookahead)
    [PR.PR_STRING, /^'(?:[^']|'')*'/, null],  // "'"

    // floating point numbers: 1, 1.0, 1i, -1.1E-1
    [PR.PR_LITERAL, /^[+\-]?\.?\d+(?:\.\d*)?(?:[Ee][+\-]?\d+)?[ij]?/, null],

    // parentheses, braces, brackets
    [PR.PR_TAG, /^(?:\{|\}|\(|\)|\[|\])/, null],  // "{}()[]"

    // other operators
    [PR.PR_PUNCTUATION, /^(?:<|>|=|~|@|&|;|,|:|!|\-|\+|\*|\^|\.|\||\\|\/)/, null]
  ];

  var identifiersPatterns = [
    // list of keywords (`iskeyword`)
    [PR.PR_KEYWORD, /^\b(?:break|case|catch|classdef|continue|else|elseif|end|for|function|global|if|otherwise|parfor|persistent|return|spmd|switch|try|while)\b/, null],

    // some specials variables/constants
    [PR_CONSTANT, /^\b(?:true|false|inf|Inf|nan|NaN|eps|pi|ans|nargin|nargout|varargin|varargout)\b/, null],

    // some data types
    [PR.PR_TYPE, /^\b(?:cell|struct|char|double|single|logical|u?int(?:8|16|32|64)|sparse)\b/, null],

    // commonly used builtin functions from core MATLAB and a few popular toolboxes
    [PR_FUNCTION, new RegExp('^\\b(?:' + coreFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + statsFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + imageFunctions + ')\\b'), null],
    [PR_FUNCTION_TOOLBOX, new RegExp('^\\b(?:' + optimFunctions + ')\\b'), null],

    // plain identifier (user-defined variable/function name)
    [PR_IDENTIFIER, /^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*/, null]
  ];

  var operatorsPatterns = [
    // forward to identifiers to match
    ["lang-matlab-identifiers", /^([a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z][a-zA-Z0-9_]*)*)/, null],

    // parentheses, braces, brackets
    [PR.PR_TAG, /^(?:\{|\}|\(|\)|\[|\])/, null],  // "{}()[]"

    // other operators
    [PR.PR_PUNCTUATION, /^(?:<|>|=|~|@|&|;|,|:|!|\-|\+|\*|\^|\.|\||\\|\/)/, null],

    // transpose operators
    [PR_TRANSPOSE, /^'/, null]
  ];

  PR.registerLangHandler(
    PR.createSimpleLexer([], identifiersPatterns),
    ["matlab-identifiers"]
  );
  PR.registerLangHandler(
    PR.createSimpleLexer([], operatorsPatterns),
    ["matlab-operators"]
  );
  PR.registerLangHandler(
    PR.createSimpleLexer(shortcutStylePatterns, fallthroughStylePatterns),
    ["matlab"]
  );
})(window['PR']);
DELIMITER";
extensions["m"] = matlab;
extensions["matlab"] = matlab;
string lua = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_STRING,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])*(?:\'|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^--(?:\[(=*)\[[\s\S]*?(?:\]\1\]|$)|[^\r\n]*)/],[PR.PR_STRING,/^\[(=*)\[[\s\S]*?(?:\]\1\]|$)/],[PR.PR_KEYWORD,/^(?:and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/,null],[PR.PR_LITERAL,/^[+-]?(?:0x[\da-f]+|(?:(?:\.\d+|\d+(?:\.\d*)?)(?:e[+\-]?\d+)?))/i],[PR.PR_PLAIN,/^[a-z_]\w*/i],[PR.PR_PUNCTUATION,/^[^\w\t\n\r \xA0][^\w\t\n\r \xA0\"\'\-\+=]*/]]),["lua"]);
DELIMITER";
extensions["lua"] = lua;
string ocaml = q"DELIMITER
PR.registerLangHandler(PR.createSimpleLexer([[PR.PR_PLAIN,/^[\t\n\r \xA0]+/,null,"  \n\r  "],[PR.PR_COMMENT,/^#(?:if[\t\n\r \xA0]+(?:[a-z_$][\w\']*|``[^\r\n\t`]*(?:``|$))|else|endif|light)/i,null,"#"],[PR.PR_STRING,/^(?:\"(?:[^\"\\]|\\[\s\S])*(?:\"|$)|\'(?:[^\'\\]|\\[\s\S])(?:\'|$))/,null,"\"'"]],[[PR.PR_COMMENT,/^(?:\/\/[^\r\n]*|\(\*[\s\S]*?\*\))/],[PR.PR_KEYWORD,/^(?:abstract|and|as|assert|begin|class|default|delegate|do|done|downcast|downto|elif|else|end|exception|extern|false|finally|for|fun|function|if|in|inherit|inline|interface|internal|lazy|let|match|member|module|mutable|namespace|new|null|of|open|or|override|private|public|rec|return|static|struct|then|to|true|try|type|upcast|use|val|void|when|while|with|yield|asr|land|lor|lsl|lsr|lxor|mod|sig|atomic|break|checked|component|const|constraint|constructor|continue|eager|event|external|fixed|functor|global|include|method|mixin|object|parallel|process|protected|pure|sealed|trait|virtual|volatile)\b/],[PR.PR_LITERAL,/^[+\-]?(?:0x[\da-f]+|(?:(?:\.\d+|\d+(?:\.\d*)?)(?:e[+\-]?\d+)?))/i],[PR.PR_PLAIN,/^(?:[a-z_][\w']*[!?#]?|``[^\r\n\t`]*(?:``|$))/i],[PR.PR_PUNCTUATION,/^[^\t\n\r \xA0\"\'\w]+/]]),["fs","ml"]);
DELIMITER";
extensions["fs"] = ocaml;
extensions["ml"] = ocaml;
```

## css

Here we determine the style of our HTMl code.

```d --- css ---
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
	font-size: 12px;
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
```d --- Weaver imports ---
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

This is the source for tangle. This compiles code from a `.md` file into runnable code. We do this by going through all the codeblocks, and storing them in an associative array. Then we apply additions and redefinitions so that the array just contains the code for each codeblock (indexed with a string: the codeblock name). Then we find the root codeblocks, i.e. the ones that are a filename, and recursively parse all the codeblocks, following each link and adding in the code for it.

Here is an overview of the file:

```d --- src/tangler.d ---
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

The `tangle` function will take a program in, go through all the chapters, sections and find all the codeblocks. It will then apply the codeblock with `+=` and `:=`. Another thing it must do is find the root blocks, that is, the files that need to be generated. Starting with those, it will recursively write code to a file using the `writeCode` function.

## The tangle function

The tangle function should find the codeblocks, apply the `+=` and `:=`, find the root codeblocks, and call `writeCode` from those.

We'll start with these three variables.

```d --- The tangle function ---
Block[string] rootCodeblocks;
Block[string] codeblocks;

getCodeblocks(p, codeblocks, rootCodeblocks);
```

Now we check if there are any root codeblocks.

```d --- The tangle function --- +=
if (rootCodeblocks.length == 0) 
{
    warn(p.file, 1, "No file codeblocks, not writing any code");
}
```

Finally we go through every root codeblock, and run writeCode on it. We open a file (making sure it is in `outDir`). We get the `commentString` from the list of commands. Then we call `writeCode`, which will recursively follow the links and generate all the code.

```d --- The tangle function --- +=
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

The writeCode function recursively follows the links inside a codeblock and writes all the code for a codeblock. It also keeps the leading whitespace to make sure indentation in the target file is correct.

```d --- The writeCode function ---
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

This file contains the source code for `main.d` the file which contains the main function for Literate. This will parse any arguments, show help text and finally run tangle or weave (or both) on any input files.

Here is an overview:

```d --- src/main.d ---
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

The arguments will consist of either flags or input files. The flags Literate accepts are:

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

We also need some variables to store these flags in, and they should be global so that the rest of the program can access them.

```d --- Globals ---
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

This program uses a number of block modifiers in order to facilitate certain functionality. For instance, if you don't wish a code block to be woven into the final HTML then the `noWeave` modifier will do this for you.

Each modifier is represented by this list of enums:

```d --- Modifiers ---
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

```d --- src/globals.d ---
@{Globals}
@{Modifiers}
```

Now, to actually parse the arguments:

```d --- Parse the arguments ---
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

To run literate we go through every file that was passed in, check if it exists, and run tangle and weave on it (unless `tangleOnly` or `weaveOnly` was specified).

```d --- Run Literate ---
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

The lit function parses the text that is inputted and then either tangles, weaves, or both. Finally it Checks for compiler errors if the `--compiler` flag was passed.

```d --- lit function ---
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

First we have to get all the codeblocks so that we can backtrack the line numbers from the error message to the correct codeblock. Then we can use the `getLinenums` function to get the line numbers for each line in the tangled code.

```d --- Check for compiler errors ---
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

```d --- Check for compiler errors --- +=
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

If there is no `@error_format` but the `@compiler` command uses a known compiler, we can substitute the error format in.

Supported compilers/linters are:

* `clang`
* `gcc`
* `g++`
* `javac`
* `pyflakes`
* `jshint`
* `dmd`
* `rustc`
* `cargo`

```d --- Check for compiler errors --- +=
if (errorFormat is null) 
{
    if (compilerCmd.indexOf("clang") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
    else if (compilerCmd.indexOf("gcc") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
    else if (compilerCmd.indexOf("g++") != -1) { errorFormat = "%f:%l:%s: %s: %m"; }
    else if (compilerCmd.indexOf("javac") != -1) { errorFormat = "%f:%l: %s: %m"; }
    else if (compilerCmd.indexOf("pyflakes") != -1) { errorFormat = "%f:%l:(%s:)? %m"; }
    else if (compilerCmd.indexOf("jshint") != -1) { errorFormat = "%f: line %l,%s, %m"; }
    else if (compilerCmd.indexOf("dmd") != -1) { errorFormat = "%f\\(%l\\):%s: %m"; }
    else if (compilerCmd.indexOf("cargo") != -1) { errorFormat = "%s --> %f:%l:%m%s"; }
    else if (compilerCmd.indexOf("rustc") != -1) { errorFormat = "%s --> %f:%l:%m%s"; }
}
```

Now we actually go through and create the regex, by replacing the `%l`, `%f`, and `%m` with matched regular expressions. Then we execute the shell command, parse each error using the error format, and rewrite the error with the proper filename and line number given by the array `codeLinenums` that we created earlier.

```d --- Check for compiler errors --- +=
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

            if (matches && linenum != "" && fname != "") 
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

Here is the `getLinenums` function. It just goes through every block like tangle would, but for each line it adds the line to the array, storing the file and line number for that line.

```d --- getLinenums function ---
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
```d --- Main imports ---
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

It has functions for reading the entire source of a file, and functions for reporting errors and warnings.

```d --- src/util.d ---
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

The `readall` function reads an entire text file, or reads from stdin until `control-d` is pressed, and returns the string.

```d --- Readall function ---
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

```d --- error function ---
void error(string file, int line, string message) 
{
    writeln(file, ":", line, ":error: ", message);
}
```

```d --- warning function ---
void warn(string file, int line, string message) 
{
    writeln(file, ":", line, ":warning: ", message);
}
```

## leadingWS function

This function returns the leading whitespace of the input string.

```d --- leadingWS function ---
string leadingWS(string str) 
{
    auto firstChar = str.indexOf(strip(str)[0]);
    return str[0..firstChar];
}
```

## getCodeblocks function

`tempCodeblocks` is an array that contains only codeblocks that have `+=` or `:=`. `rootCodeblocks` and `codeblocks` are both associative arrays which will hold more important information. `codeblocks` will contain every codeblock after the `+=` and `:=` transformations have been applied.

Here we go through every single block in the program, and add it to the `tempCodeblocks` array if it has a `+=` or `:=`. Otherwise, we add it to the `codeblocks` array, and if it matches the filename regex `.*\.\w+`, we add it to the `rootCodeblocks` array.

```d --- getCodeblocks function ---
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

This function returns the html file for a chapter given the major and minor numbers for it. The minor and major nums are passed in as a string formatted as: `major.minor`.

```d --- getChapterHtmlFile function ---
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

# How to build

Building Literate is done by a simple Makefile that is edited manually. The build dependencies are listed here below in this section. It seems to be a better overall philosophy to build everything manually than to use a system that shadows a lot of the details - this generally hinders understanding significantly.

```make --- Makefile -comment ---
Literate.html: Literate.md
	bin/lit Literate.md

fullbuild: Literate.html $(sources)
	dmd $(sources) -od=obj -of=bin/lit 
	bin/lit Literate.md

build: $(sources)
	dmd $(sources) -od=obj -of=bin/lit

sources = src/globals.d \
		  src/main.d \
		  src/parser.d \
		  src/tangler.d \
		  src/util.d \
		  src/weaver.d \
		  src/dmarkdown/html.d \
		  src/dmarkdown/markdown.d \
		  src/dmarkdown/package.d \
		  src/dmarkdown/string.d
```
