# Agent rules

These rules apply to every AI agent that works in a repository holding
this file. Each such repository holds the same file, byte for byte. Do
not change it in one repository alone; propose the change to the user
instead. Where the repository's own instructions or the user's explicit
instructions differ from these rules, those instructions take precedence.

## 1. Simple code and plain comments

Keep code and comments simple and clear. Use a complex construct, an
uncommon word or a long sentence only when the context, a requirement or
a constraint calls for it.

- In code, build each part from short, clear statements that each do one
  thing. Prefer common, conventional forms and names that state their
  meaning. Avoid constructs that allow more than one reading or that make
  the reader stop to work out what they do.
- In comments, use plain words and short sentences, with one point per
  sentence. Connect the sentences in a logical order that the reader can
  follow.

## 2. Code that explains itself

- Make code and scripts explain themselves: improve names and structure
  before you add a comment.
- Add a comment only where the code alone is not enough to understand it:
  background knowledge that the code relies on, the reason for an
  operation or for an implementation that looks unnecessary, a complex
  implementation, or a case analysis with many branches. State what the
  code does and why, and leave how it does it to the code.
- Code that serves as a public interface or as teaching material may
  carry longer comments that describe its behavior, arguments, return
  values and cases in detail.

## 3. Checks in every task

In every task, such as adding a feature, refactoring or auditing
security, check the following points.

1. Errors of judgment: check each conclusion for a false positive (Type I
   error) and a false negative (Type II error).
2. Side effects: check whether the change can create a larger problem
   than the one it solves, for example by moving the problem into another
   part of the system. Integrate the change with the existing features,
   and leave room for the extensions that the project needs.
3. Generality: decide how general and extensible the design must be. Do
   not build a general, extensible design for code that needs none, such
   as a self-contained example written for learning. Do not hard-wire a
   design that must grow, such as a library or an expanding system. This
   judgment is subjective: ask the user when the criterion is unclear, or
   when nothing on record (the project, its history or the user's earlier
   instructions) shows the user's preferences, principles or style.
4. Security: check whether the code that you add or refactor, or the code
   that you review in an audit, can become a security vulnerability.

## 4. No hard-coded values

Weigh the trade-offs, and avoid hard-coding where you can. Do not write
magic numbers or literal strings directly into the code. Give each value
a name, or read it from configuration or from the system. Apply this rule
more strictly as the project grows.

## 5. The project's conventions first

- Without an instruction from the user, do not introduce a coding style
  or a project structure from your own training. Follow the explicit and
  implicit conventions that the git history and the existing files show:
  the style of the code and scripts, the commit messages, the pull
  requests and other working practices. Build on the project's existing
  management practices and build system.
- When the user's instruction conflicts with the existing structure, or
  the structure lacks a needed function or blocks a required extension,
  you may propose a substantial refactoring. Carry it out only after the
  user explicitly approves it.
