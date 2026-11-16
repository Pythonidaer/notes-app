import { Extension, Mark, Node, mergeAttributes } from "@tiptap/core";
import { Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";
import { BulletList } from "@tiptap/extension-bullet-list";
import { Paragraph } from "@tiptap/extension-paragraph";
import { Placeholder } from "@tiptap/extension-placeholder";
import { TaskItem } from "@tiptap/extension-task-item";
import { TaskList } from "@tiptap/extension-task-list";
import { Color, TextStyle } from "@tiptap/extension-text-style";
import { TableKit } from "@tiptap/extension-table";
import { StarterKit } from "@tiptap/starter-kit";

const blockChild = new Set([
  "P",
  "DIV",
  "UL",
  "OL",
  "LI",
  "BLOCKQUOTE",
  "PRE",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
  "TABLE",
  "HR",
  "FIGURE",
  "SECTION",
  "ARTICLE",
  "ASIDE",
  "HEADER",
  "FOOTER",
  "NAV",
  "MAIN",
  "FORM",
  "FIELDSET",
  "ADDRESS",
  "DL",
  "DT",
  "DD",
]);

export const noteDateKey = new PluginKey("noteDate");
export const noteFindKey = new PluginKey("noteFind");

function escapeFindTerm(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function findMatches(doc, query) {
  const needle = String(query || "");
  if (!needle) return [];
  const expression = new RegExp(escapeFindTerm(needle), "giu");
  const ranges = [];
  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return;
    expression.lastIndex = 0;
    let match = expression.exec(node.text);
    while (match) {
      const length = match[0].length;
      if (length > 0) {
        ranges.push({ from: pos + match.index, to: pos + match.index + length });
      }
      if (expression.lastIndex === match.index) expression.lastIndex += 1;
      match = expression.exec(node.text);
    }
  });
  return ranges;
}

const NoteFind = Extension.create({
  name: "noteFind",
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: noteFindKey,
        state: {
          init: () => ({ query: "", index: 0, matches: [] }),
          apply(transaction, value) {
            const meta = transaction.getMeta(noteFindKey);
            if (meta && meta.clear) return { query: "", index: 0, matches: [] };
            let query = value.query;
            let index = value.index;
            if (meta && typeof meta.query === "string") {
              query = meta.query;
              index = 0;
            }
            if (meta && Number.isInteger(meta.index)) index = meta.index;
            const matches = findMatches(transaction.doc, query);
            if (!matches.length) index = 0;
            else index = ((index % matches.length) + matches.length) % matches.length;
            return { query, index, matches };
          },
        },
        props: {
          decorations(state) {
            const found = noteFindKey.getState(state);
            if (!found || !found.matches.length) return DecorationSet.empty;
            const marks = found.matches.map((match, index) =>
              Decoration.inline(match.from, match.to, {
                class: index === found.index ? "find-match find-match-current" : "find-match",
              })
            );
            return DecorationSet.create(state.doc, marks);
          },
        },
      }),
    ];
  },
});

const NoteDate = Extension.create({
  name: "noteDate",
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: noteDateKey,
        state: {
          init: () => "",
          apply(transaction, value) {
            const next = transaction.getMeta(noteDateKey);
            return typeof next === "string" ? next : value;
          },
        },
        props: {
          decorations(state) {
            const text = noteDateKey.getState(state);
            if (!text) return DecorationSet.empty;
            const widget = Decoration.widget(
              0,
              () => {
                const label = document.createElement("p");
                label.id = "note-date";
                label.className = "note-date";
                label.setAttribute("contenteditable", "false");
                label.textContent = text;
                return label;
              },
              { side: -1, ignoreSelection: true, key: text }
            );
            return DecorationSet.create(state.doc, [widget]);
          },
        },
      }),
    ];
  },
});

const NoteTitle = Node.create({
  name: "noteTitle",
  priority: 1000,
  group: "block",
  content: "inline*",
  defining: true,
  parseHTML() {
    return [{ tag: "p[data-note-title]" }];
  },
  renderHTML({ HTMLAttributes }) {
    return ["p", mergeAttributes(HTMLAttributes, { class: "note-title", "data-note-title": "true" }), 0];
  },
});

const ParagraphWithDiv = Paragraph.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      transcriptFor: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-nn-transcript-for"),
        renderHTML: (attributes) => {
          if (!attributes.transcriptFor) {
            return {};
          }
          return { "data-nn-transcript-for": attributes.transcriptFor };
        },
      },
    };
  },
  parseHTML() {
    return [
      { tag: "p" },
      {
        tag: "div",
        getAttrs: (element) => {
          const children = [...element.children];
          const hasBlock = children.some((child) => blockChild.has(child.tagName));
          if (hasBlock) {
            return false;
          }
          return {};
        },
      },
    ];
  },
});

const noteAudio = Node.create({
  name: "noteAudio",
  group: "block",
  atom: true,
  draggable: true,
  selectable: true,
  addAttributes() {
    return {
      storagePath: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-nn-storage-path"),
        renderHTML: (attrs) =>
          attrs.storagePath ? { "data-nn-storage-path": attrs.storagePath } : {},
      },
      fileName: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-nn-file-name") ?? "",
        renderHTML: (attrs) => (attrs.fileName ? { "data-nn-file-name": attrs.fileName } : {}),
      },
      mimeType: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-nn-mime-type") ?? "",
        renderHTML: (attrs) => (attrs.mimeType ? { "data-nn-mime-type": attrs.mimeType } : {}),
      },
      sizeBytes: {
        default: null,
        parseHTML: (element) => {
          const value = element.getAttribute("data-nn-size-bytes");
          if (value == null || value === "") {
            return null;
          }
          const parsed = Number.parseInt(value, 10);
          return Number.isFinite(parsed) ? parsed : null;
        },
        renderHTML: (attrs) =>
          attrs.sizeBytes != null ? { "data-nn-size-bytes": String(attrs.sizeBytes) } : {},
      },
      uploadedAt: {
        default: "",
        parseHTML: (element) => element.getAttribute("data-nn-uploaded-at") ?? "",
        renderHTML: (attrs) =>
          attrs.uploadedAt ? { "data-nn-uploaded-at": attrs.uploadedAt } : {},
      },
    };
  },
  parseHTML() {
    return [
      {
        tag: "figure.nn-audio-embed",
        getAttrs: (element) => (element.getAttribute("data-nn-storage-path") ? {} : false),
      },
    ];
  },
  renderHTML({ node, HTMLAttributes }) {
    const label =
      (node.attrs.fileName && String(node.attrs.fileName).trim()) || "Audio clip";
    return [
      "figure",
      mergeAttributes(HTMLAttributes, { class: "nn-audio-embed" }),
      ["figcaption", { class: "nn-audio-caption" }, label],
    ];
  },
  addNodeView() {
    return ({ node }) => {
      const figure = document.createElement("figure");
      figure.className = "nn-audio-embed";
      figure.setAttribute("contenteditable", "false");
      const path = node.attrs.storagePath || "";
      if (path) figure.setAttribute("data-nn-storage-path", path);
      const audio = document.createElement("audio");
      audio.controls = true;
      audio.preload = "metadata";
      if (path) audio.src = audioSource(path);
      figure.appendChild(audio);
      return {
        dom: figure,
        update(updated) {
          return updated.type.name === "noteAudio";
        },
        ignoreMutation() {
          return true;
        },
        stopEvent(event) {
          const target = event.target;
          return target instanceof Element && Boolean(target.closest("audio"));
        },
      };
    };
  },
});

function audioSource(storagePath) {
  return `notes-audio://clip?path=${encodeURIComponent(storagePath)}`;
}

const StandardBulletList = BulletList.extend({
  parseHTML() {
    return [
      {
        tag: "ul",
        getAttrs: (element) => (element.getAttribute("data-list") === "dash" ? false : null),
      },
    ];
  },
});

const DashList = BulletList.extend({
  name: "dashList",
  priority: 200,
  parseHTML() {
    return [{ tag: 'ul[data-list="dash"]' }];
  },
  renderHTML({ HTMLAttributes }) {
    return [
      "ul",
      mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, {
        "data-list": "dash",
        class: "dash-list",
      }),
      0,
    ];
  },
  addCommands() {
    return {
      toggleDashList:
        () =>
        ({ commands }) =>
          commands.toggleList(this.name, this.options.itemTypeName),
    };
  },
  addKeyboardShortcuts() {
    return {};
  },
  addInputRules() {
    return [];
  },
});

export const highlightColors = {
  purple: true,
  pink: true,
  orange: true,
  mint: true,
  blue: true,
};

const Highlight = Mark.create({
  name: "highlight",
  addAttributes() {
    return {
      color: {
        default: null,
        parseHTML: (element) => {
          const named = element.getAttribute("data-color");
          return named && highlightColors[named] ? named : null;
        },
        renderHTML: (attributes) => {
          if (!highlightColors[attributes.color]) {
            return {};
          }
          return { "data-color": attributes.color };
        },
      },
    };
  },
  parseHTML() {
    return [
      {
        tag: "mark",
        getAttrs: (element) => {
          const named = element.getAttribute("data-color");
          return named && highlightColors[named] ? null : false;
        },
      },
    ];
  },
  renderHTML({ HTMLAttributes }) {
    return ["mark", mergeAttributes(HTMLAttributes), 0];
  },
});

export const extensions = [
  NoteDate,
  StarterKit.configure({
    paragraph: false,
    bulletList: false,
    heading: { levels: [1, 2, 3] },
    link: {
      openOnClick: false,
      autolink: true,
      HTMLAttributes: { rel: "noopener noreferrer", target: "_blank" },
    },
    codeBlock: {
      HTMLAttributes: {
        class: "nn-code-block",
      },
    },
  }),
  NoteTitle,
  ParagraphWithDiv,
  StandardBulletList,
  DashList,
  TextStyle,
  Color.configure({ types: ["textStyle"] }),
  Highlight,
  TaskList,
  TaskItem.configure({ nested: true }),
  Placeholder.configure({
    placeholder: ({ node }) => (node.type.name === "noteTitle" ? "Title" : "Write"),
  }),
  TableKit.configure({
    table: { resizable: true, cellMinWidth: 48 },
  }),
  noteAudio,
  NoteFind,
];
