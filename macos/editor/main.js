import { Editor } from "@tiptap/core";
import DOMPurify from "dompurify";
import { Fragment } from "@tiptap/pm/model";
import { EditorState, TextSelection } from "@tiptap/pm/state";
import { createTable } from "@tiptap/extension-table";

import { extensions, highlightColors, noteDateKey, noteFindKey } from "./extensions.js";
import "./editor.css";

let quiet = false;

const editor = new Editor({
  element: document.querySelector("#editor"),
  extensions,
  content: "<p></p>",
  editorProps: {
    attributes: {
      class: "noteText",
      "aria-label": "Note body",
    },
    handleDoubleClick(view, pos, event) {
      if (selectTitleAt(view, pos, event)) return true;
      const target = event.target instanceof Element ? event.target : event.target?.parentElement;
      if (!target?.closest?.("[data-note-title], .note-title")) return false;
      return selectNoteTitle(view);
    },
    handleKeyDown(view, event) {
      if (event.key === "Enter") return splitTitle(view);
      if (event.key === "Backspace") return keepTitle(view);
      return false;
    },
  },
});

const purifyConfig = {
  USE_PROFILES: { html: true },
  ADD_ATTR: [
    "style",
    "target",
    "rel",
    "controls",
    "preload",
    "class",
    "data-list",
    "data-nn-storage-path",
    "data-nn-file-name",
    "data-nn-mime-type",
    "data-nn-size-bytes",
    "data-nn-uploaded-at",
    "data-nn-transcript-for",
    "data-color",
    "data-note-title",
    "colwidth",
    "colspan",
    "rowspan",
  ],
  ADD_TAGS: ["figure", "figcaption", "audio", "source"],
};

function sanitized(html) {
  return DOMPurify.sanitize(html, purifyConfig);
}

function titleText() {
  let text = "";
  editor.state.doc.forEach((node) => {
    if (!text && node.type.name === "noteTitle") text = node.textContent;
  });
  return text;
}

function bodyHTML() {
  const root = document.createElement("div");
  root.innerHTML = editor.getHTML();
  root.querySelectorAll("[data-note-title]").forEach((node) => node.remove());
  return sanitized(root.innerHTML);
}

function postChange() {
  if (quiet) return;
  const handler = window.webkit?.messageHandlers?.noteChanged;
  if (!handler) return;
  handler.postMessage(JSON.stringify({ title: titleText(), html: bodyHTML() }));
}

editor.on("update", postChange);

document.querySelector("#editor").addEventListener("mousedown", (event) => {
  if (event.target === event.currentTarget) {
    editor.commands.focus("end");
  }
});

editor.view.dom.addEventListener(
  "dblclick",
  (event) => {
    const target = event.target instanceof Element ? event.target : event.target?.parentElement;
    const title = target?.closest?.("[data-note-title], .note-title");
    if (!title || !editor.view.dom.contains(title)) return;
    if (selectNoteTitle(editor.view)) {
      event.preventDefault();
      event.stopPropagation();
    }
  },
  true
);

function runQuiet(work) {
  quiet = true;
  try {
    work();
  } finally {
    quiet = false;
  }
}

function replaceDocument(tr, state, nodes) {
  tr.replaceWith(0, state.doc.content.size, Fragment.from(nodes));
}

function titleNode(schema, text) {
  const value = String(text ?? "").replace(/\r?\n/g, " ");
  if (!value) return schema.nodes.noteTitle.create();
  return schema.nodes.noteTitle.create(null, schema.text(value));
}

function showDate(text) {
  const next = String(text ?? "");
  const current = noteDateKey.getState(editor.state) ?? "";
  if (current === next) return;
  editor.view.dispatch(editor.state.tr.setMeta(noteDateKey, next).setMeta("addToHistory", false));
}

function loadNote(title, html) {
  const holder = document.createElement("div");
  holder.innerHTML = html && String(html).trim() ? String(html) : "<p></p>";
  holder.querySelectorAll("[data-note-title]").forEach((node) => node.remove());
  const cleaned = holder.innerHTML.trim() || "<p></p>";
  runQuiet(() => {
    editor.commands.setContent(cleaned, { emitUpdate: false });
    const node = titleNode(editor.schema, title);
    editor.view.dispatch(editor.state.tr.insert(0, node));
    // One editor serves every note. Opening a note must leave the undo stack empty,
    // or Command-Z restores the note that was open before this one.
    dropUndoHistory();
  });
}

function dropUndoHistory() {
  const date = noteDateKey.getState(editor.state) ?? "";
  const fresh = EditorState.create({
    doc: editor.state.doc,
    selection: editor.state.selection,
    storedMarks: editor.state.storedMarks,
    plugins: editor.state.plugins,
  });
  editor.view.updateState(fresh);
  showDate(date);
}

function selectedBlock(state) {
  const { $from } = state.selection;
  if (!$from.parent.isTextblock) return null;
  return { node: $from.parent, pos: $from.before($from.depth), depth: $from.depth };
}

function applyTitle() {
  const block = selectedBlock(editor.state);
  if (!block) return false;
  if (block.node.type.name === "noteTitle") return true;
  return editor
    .chain()
    .focus()
    .command(({ state, tr }) => {
      const current = selectedBlock(state);
      if (!current || current.node.type.name === "noteTitle") return true;
      const schema = state.schema;
      const noteTitle = schema.nodes.noteTitle;
      const paragraph = schema.nodes.paragraph;
      if (current.depth !== 1) {
        const nodes = [];
        let replaced = false;
        const nextTitle = noteTitle.create(null, current.node.content);
        state.doc.forEach((node) => {
          if (!replaced && node.type.name === "noteTitle") {
            nodes.push(nextTitle);
            replaced = true;
          } else {
            nodes.push(node);
          }
        });
        if (!replaced) nodes.unshift(nextTitle);
        replaceDocument(tr, state, nodes);
        return true;
      }
      const nodes = [];
      let chosen = null;
      state.doc.forEach((node, offset) => {
        if (offset === current.pos) {
          chosen = noteTitle.create(null, node.content);
          return;
        }
        if (node.type.name === "noteTitle") nodes.push(paragraph.create(null, node.content));
        else nodes.push(node);
      });
      if (!chosen) return false;
      replaceDocument(tr, state, [chosen, ...nodes]);
      const cursor = Math.max(1, chosen.nodeSize - 1);
      tr.setSelection(TextSelection.create(tr.doc, cursor));
      return true;
    })
    .run();
}

function applyStyledBlock(name) {
  if (!editor.isActive("noteTitle")) {
    const chain = editor.chain().focus();
    if (name === "heading") return chain.setHeading({ level: 2 }).run();
    if (name === "subheading") return chain.setHeading({ level: 3 }).run();
    return chain.setParagraph().run();
  }
  return editor
    .chain()
    .focus()
    .command(({ state, tr }) => {
      const current = selectedBlock(state);
      if (!current || current.node.type.name !== "noteTitle") return false;
      const schema = state.schema;
      const type =
        name === "body" ? schema.nodes.paragraph : schema.nodes.heading;
      const attrs = name === "heading" ? { level: 2 } : name === "subheading" ? { level: 3 } : null;
      const converted = type.create(attrs, current.node.content);
      const nodes = [];
      let placed = false;
      state.doc.forEach((node, offset) => {
        if (offset === current.pos) {
          if (!placed) {
            nodes.push(schema.nodes.noteTitle.create());
            placed = true;
          }
          nodes.push(converted);
          return;
        }
        nodes.push(node);
      });
      if (!placed) nodes.unshift(schema.nodes.noteTitle.create());
      replaceDocument(tr, state, nodes);
      return true;
    })
    .run();
}

function runCommand(command) {
  const chain = editor.chain().focus();
  if (command === "bold") chain.toggleBold().run();
  else if (command === "italic") chain.toggleItalic().run();
  else if (command === "underline") chain.toggleUnderline().run();
  else if (command === "strike") chain.toggleStrike().run();
  else if (command === "title") applyTitle();
  else if (command === "heading" || command === "subheading" || command === "body") applyStyledBlock(command);
  else if (command === "monostyled") chain.toggleCodeBlock().run();
  else if (command === "bullet") chain.toggleBulletList().run();
  else if (command === "dash") chain.toggleDashList().run();
  else if (command === "ordered") chain.toggleOrderedList().run();
  else if (command === "quote") chain.toggleBlockquote().run();
  else if (command === "task") chain.toggleTaskList().run();
  else if (command === "table") insertNoteTable();
  else if (command.startsWith("highlight:")) {
    const name = command.slice("highlight:".length);
    if (!highlightColors[name]) return;
    const current = String(editor.getAttributes("highlight").color || "");
    if (current === name) chain.unsetMark("highlight").run();
    else chain.setMark("highlight", { color: name }).run();
  }
}

function formatState() {
  let block = "body";
  if (editor.isActive("noteTitle")) block = "title";
  else if (editor.isActive("codeBlock")) block = "monostyled";
  else if (editor.isActive("heading")) {
    const level = Number(editor.getAttributes("heading").level) || 0;
    if (level === 2) block = "heading";
    else if (level === 3) block = "subheading";
    else block = "legacy-heading";
  }
  const highlight = String(editor.getAttributes("highlight").color || "");
  return {
    bold: editor.isActive("bold"),
    italic: editor.isActive("italic"),
    underline: editor.isActive("underline"),
    strike: editor.isActive("strike"),
    block,
    highlight: highlightColors[highlight] ? highlight : "",
  };
}

function selectTitleRange(view, from, to) {
  const doc = view.state.doc;
  const selection =
    from >= to ? TextSelection.create(doc, from) : TextSelection.create(doc, from, to);
  view.dispatch(view.state.tr.setSelection(selection));
  return true;
}

function selectTitleAt(view, pos, event) {
  const doc = view.state.doc;
  if (doc.content.size === 0) return false;
  const clamped = Math.max(0, Math.min(pos, doc.content.size));
  const $pos = doc.resolve(clamped);
  for (let depth = $pos.depth; depth > 0; depth -= 1) {
    if ($pos.node(depth).type.name !== "noteTitle") continue;
    if (event) event.preventDefault();
    return selectTitleRange(view, $pos.start(depth), $pos.end(depth));
  }
  return false;
}

function selectNoteTitle(view) {
  let found = null;
  view.state.doc.descendants((node, pos) => {
    if (found) return false;
    if (node.type.name === "noteTitle") found = { node, pos };
    return true;
  });
  if (!found) return false;
  return selectTitleRange(view, found.pos + 1, found.pos + found.node.nodeSize - 1);
}

function splitTitle(view) {
  const { state } = view;
  if (view.composing) return false;
  const { $from, $to } = state.selection;
  if (!$from.sameParent($to) || $from.parent.type.name !== "noteTitle") return false;
  let tr = state.tr;
  if (!state.selection.empty) tr = tr.deleteSelection();
  const at = tr.selection.$from;
  if (at.parent.type.name !== "noteTitle") return false;
  const parent = at.parent;
  const pos = at.before();
  const offset = at.parentOffset;
  const before = parent.cut(0, offset);
  const after = parent.cut(offset);
  const title = state.schema.nodes.noteTitle.create(null, before.content);
  const paragraph = state.schema.nodes.paragraph.create(
    null,
    after.content.size ? after.content : null
  );
  tr = tr.replaceWith(pos, pos + parent.nodeSize, Fragment.from([title, paragraph]));
  const cursor = pos + title.nodeSize + 1;
  tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(cursor, tr.doc.content.size))));
  view.dispatch(tr.scrollIntoView());
  return true;
}

function keepTitle(view) {
  if (view.composing) return false;
  const { selection } = view.state;
  if (!selection.empty) return false;
  const { $from } = selection;
  if ($from.parent.type.name !== "noteTitle" || $from.parentOffset > 0) return false;
  return true;
}

function insertNoteTable() {
  if (!editor.isActive("table")) {
    return editor.chain().focus().insertTable({ rows: 2, cols: 2, withHeaderRow: false }).run();
  }
  return editor
    .chain()
    .focus()
    .command(({ state, tr }) => {
      const { $from } = state.selection;
      let depth = $from.depth;
      while (depth > 0 && $from.node(depth).type.name !== "table") depth -= 1;
      if (depth === 0) return false;
      const pos = $from.after(depth);
      const table = createTable(state.schema, 2, 2, false);
      tr.insert(pos, table);
      const cursor = Math.min(pos + 2, tr.doc.content.size);
      tr.setSelection(TextSelection.near(tr.doc.resolve(cursor)));
      return true;
    })
    .run();
}

function selectText(text) {
  const needle = String(text);
  let found = null;
  editor.state.doc.descendants((node, pos) => {
    if (found != null) return false;
    if (node.isText && node.text?.includes(needle)) found = pos + node.text.indexOf(needle);
    return true;
  });
  if (found == null) return false;
  editor.chain().focus().setTextSelection(found).run();
  return true;
}

function findState() {
  return noteFindKey.getState(editor.state) || { query: "", index: 0, matches: [] };
}

function findSummary() {
  const state = findState();
  return JSON.stringify({
    count: state.matches.length,
    index: state.matches.length ? state.index : 0,
  });
}

function revealCurrentFind() {
  const current = editor.view.dom.querySelector(".find-match-current");
  current?.scrollIntoView({ block: "nearest", inline: "nearest" });
}

function setFindQuery(query) {
  editor.view.dispatch(
    editor.state.tr.setMeta(noteFindKey, { query: String(query ?? "") }).setMeta("addToHistory", false)
  );
  return findSummary();
}

function moveFind(delta) {
  const state = findState();
  if (!state.matches.length) return findSummary();
  const index = state.index < 0
    ? (delta < 0 ? state.matches.length - 1 : 0)
    : (state.index + delta + state.matches.length) % state.matches.length;
  editor.view.dispatch(editor.state.tr.setMeta(noteFindKey, { index }).setMeta("addToHistory", false));
  revealCurrentFind();
  return findSummary();
}

function replaceCurrentFind(replacement) {
  const state = findState();
  const match = state.index < 0 ? null : state.matches[state.index];
  if (!match) return findSummary();
  const tr = editor.state.tr.insertText(String(replacement ?? ""), match.from, match.to);
  tr.setMeta(noteFindKey, { index: state.index });
  editor.view.dispatch(tr);
  revealCurrentFind();
  return findSummary();
}

function replaceEveryFind(replacement) {
  const state = findState();
  if (!state.matches.length) return findSummary();
  let tr = editor.state.tr;
  const text = String(replacement ?? "");
  for (let index = state.matches.length - 1; index >= 0; index -= 1) {
    const match = state.matches[index];
    tr = tr.insertText(text, tr.mapping.map(match.from), tr.mapping.map(match.to));
  }
  tr.setMeta(noteFindKey, { index: -1 });
  editor.view.dispatch(tr);
  revealCurrentFind();
  return findSummary();
}

function clearFindHighlights() {
  editor.view.dispatch(editor.state.tr.setMeta(noteFindKey, { clear: true }).setMeta("addToHistory", false));
}

window.notesEditor = {
  setHTML(html) {
    runQuiet(() => {
      editor.commands.setContent(html && String(html).trim() ? html : "<p></p>", {
        emitUpdate: false,
      });
    });
  },
  setNote(title, html, dateHeading) {
    if (typeof dateHeading === "string") showDate(dateHeading);
    loadNote(title, html);
  },
  focusStart() {
    editor.commands.focus("start");
  },
  undo() {
    return editor.chain().focus().undo().run();
  },
  getHTML() {
    return bodyHTML();
  },
  getTitle() {
    return titleText();
  },
  insertText(text) {
    editor.chain().focus("start").insertContent(text).run();
  },
  insertHTML(html) {
    editor.chain().focus().insertContent(String(html || "")).run();
  },
  format(command) {
    runCommand(String(command || ""));
  },
  selectAll() {
    editor.chain().focus().selectAll().run();
  },
  selectText(text) {
    return selectText(text);
  },
  find(query) {
    return setFindQuery(query);
  },
  findNext() {
    return moveFind(1);
  },
  findPrevious() {
    return moveFind(-1);
  },
  replaceCurrent(text) {
    return replaceCurrentFind(text);
  },
  replaceAll(text) {
    return replaceEveryFind(text);
  },
  clearFind() {
    clearFindHighlights();
  },
  selectionText() {
    const { from, to } = editor.state.selection;
    return editor.state.doc.textBetween(from, to, "\n");
  },
  formatState() {
    return JSON.stringify(formatState());
  },
};

const fontsReady = document.fonts?.ready ?? Promise.resolve();
fontsReady.then(() => {
  window.notesEditorReady = true;
});
