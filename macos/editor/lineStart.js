import { TextSelection } from "@tiptap/pm/state";

/**
 * Whether an opened note gets an empty Title line at the top.
 *
 * A note with no title and some body text opens in Body, so a click near the top does not land
 * in a large empty Title line. An empty note keeps the Title line, so typing starts the title.
 */
export function needsTitleLine(title, doc) {
  if (String(title ?? "").trim()) return true;
  const only = doc.childCount === 1 ? doc.firstChild : null;
  return Boolean(only && only.isTextblock && only.content.size === 0);
}

/**
 * Backspace with the caret at the start of a line. Returns true when the key was handled.
 *
 * - A Title with text has nothing before it, so Backspace does nothing.
 * - An empty Title is removed and the caret moves to the Body line below it.
 * - A Heading, Subheading, or legacy H1 becomes Body. The next Backspace joins it to the line above.
 */
export function backspaceAtLineStart(state, dispatch) {
  const { selection } = state;
  if (!selection.empty) return false;
  const { $from } = selection;
  if ($from.parentOffset > 0) return false;
  const line = $from.parent;
  const paragraph = state.schema.nodes.paragraph;

  if (line.type.name === "noteTitle") {
    if (line.content.size > 0) return true;
    if (dispatch) {
      const start = $from.before();
      const tr = state.tr;
      if (state.doc.childCount > 1 && $from.depth === 1) {
        tr.delete(start, start + line.nodeSize);
      } else {
        tr.setBlockType(start, start + line.nodeSize, paragraph);
      }
      tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(start + 1, tr.doc.content.size))));
      dispatch(tr.scrollIntoView());
    }
    return true;
  }

  if (line.type.name === "heading") {
    if (dispatch) {
      const start = $from.before();
      dispatch(state.tr.setBlockType(start, start + line.nodeSize, paragraph).scrollIntoView());
    }
    return true;
  }

  return false;
}
