import assert from "node:assert/strict";
import { test } from "node:test";

import { getSchema } from "@tiptap/core";
import { EditorState, TextSelection } from "@tiptap/pm/state";

import { extensions } from "./extensions.js";
import { backspaceAtLineStart, needsTitleLine } from "./lineStart.js";

const schema = getSchema(extensions);

function line(type, text, attrs = null) {
  return schema.nodes[type].create(attrs, text ? schema.text(text) : null);
}

function stateAt(lines, caret) {
  const doc = schema.node("doc", null, lines);
  return EditorState.create({ doc, selection: TextSelection.create(doc, caret) });
}

function backspace(state) {
  let next = state;
  const handled = backspaceAtLineStart(state, (tr) => {
    next = state.apply(tr);
  });
  return { handled, state: next };
}

function outline(state) {
  const lines = [];
  state.doc.forEach((node) => lines.push(`${node.type.name}:${node.textContent}`));
  return lines;
}

test("an empty Title above Body text is removed and the caret lands in Body", () => {
  const start = stateAt([line("noteTitle"), line("paragraph", "Hello")], 1);
  const { handled, state } = backspace(start);
  assert.equal(handled, true);
  assert.deepEqual(outline(state), ["paragraph:Hello"]);
  assert.equal(state.selection.$from.parent.type.name, "paragraph");
  assert.equal(state.selection.$from.parentOffset, 0);
});

test("an empty Title that is the only line becomes Body", () => {
  const start = stateAt([line("noteTitle")], 1);
  const { handled, state } = backspace(start);
  assert.equal(handled, true);
  assert.deepEqual(outline(state), ["paragraph:"]);
});

test("a Title with text stays put", () => {
  const start = stateAt([line("noteTitle", "Set list"), line("paragraph", "Hello")], 1);
  const { handled, state } = backspace(start);
  assert.equal(handled, true);
  assert.equal(state, start);
});

test("a Heading at the start of its line becomes Body", () => {
  for (const level of [1, 2, 3]) {
    const lines = [line("noteTitle", "Set list"), line("paragraph", "Intro"), line("heading", "Closer", { level })];
    const caret = lines[0].nodeSize + lines[1].nodeSize + 1;
    const { handled, state } = backspace(stateAt(lines, caret));
    assert.equal(handled, true);
    assert.deepEqual(outline(state), ["noteTitle:Set list", "paragraph:Intro", "paragraph:Closer"]);
  }
});

test("Body text and a caret inside a line use the normal Backspace", () => {
  const lines = [line("noteTitle", "Set list"), line("paragraph", "Hello"), line("heading", "Closer", { level: 2 })];
  const bodyStart = lines[0].nodeSize + 1;
  assert.equal(backspace(stateAt(lines, bodyStart)).handled, false);
  assert.equal(backspace(stateAt(lines, bodyStart + 2)).handled, false);
  const insideHeading = lines[0].nodeSize + lines[1].nodeSize + 3;
  assert.equal(backspace(stateAt(lines, insideHeading)).handled, false);
});

test("only an empty note or a note with a title opens with a Title line", () => {
  const empty = schema.node("doc", null, [line("paragraph")]);
  const withBody = schema.node("doc", null, [line("paragraph", "Hello")]);
  assert.equal(needsTitleLine("", empty), true);
  assert.equal(needsTitleLine("Set list", withBody), true);
  assert.equal(needsTitleLine("", withBody), false);
  assert.equal(needsTitleLine("   ", withBody), false);
});
