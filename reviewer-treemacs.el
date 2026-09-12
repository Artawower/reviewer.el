;;; reviewer-treemacs.el --- Treemacs tree/detail view for reviewer.el  -*- lexical-binding: t -*-

;; Copyright (C) 2026

;; Author: Sreenivas Venkobarao
;; URL: https://github.com/SreenivasVRao/reviewer.el
;; Package-Requires: ((emacs "29.1") (treemacs "3.0") (reviewer "0"))

;;; Commentary:

;; Prototype of a persistent, two-pane alternative to the posframe popup:
;; a treemacs tree of annotation threads docked to one side of the
;; frame, with a plain detail pane stacked directly beneath it showing
;; the selected thread's full text.  The two windows share a side
;; (`left' or `right', see `reviewer-treemacs-side') at adjacent slots,
;; are marked dedicated and `no-delete-other-windows', and are toggled
;; together by `reviewer-treemacs-toggle' (also bound to "q" in both
;; panes) -- so from the user's perspective they're one locked unit,
;; not two independent side windows that happen to be adjacent.
;;
;; Moving point onto a thread -- with n/p, arrows, or a mouse click --
;; previews it in the detail pane immediately, no RET required.  File
;; nodes are just group headers, not independently selectable, so n/p
;; skip over them straight to the next/previous thread; arrows and
;; mouse clicks still land on them as ordinary treemacs branch nodes,
;; e.g. to expand/collapse.  RET jumps to the thread's source location
;; and shows it there too -- highlight, popup -- but by default leaves
;; the tree window selected, so n/p keep driving straight through a
;; string of threads without an explicit switch back; set
;; `reviewer-treemacs-ret-moves-focus' non-nil to have RET switch
;; focus there instead.  "o o" always jumps and switches focus
;; regardless of that setting, "o v"/"o h" open it in a fresh
;; vertical/horizontal split instead, and "o c" jumps then closes the
;; tree/detail pane, mirroring vanilla treemacs's own "o" submap
;; without the file-management variants that don't apply to a thread.
;; "r" on a thread opens a small reply pane, stacked below the other
;; two, to append to it.
;; "q" (or "C-g", bound the same in both panes) kills the tree/detail
;; buffers outright rather than just burying them, so reopening always
;; starts from a clean `treemacs-initialize'.  `reviewer-transient'
;; also gets a "t" suffix for the same toggle.
;;
;; This is a skeleton: the tree currently renders placeholder data
;; (`reviewer-treemacs--dummy-data'), not real `reviewer-mode'
;; annotations.  Wiring it to `reviewer-all-annotations' across project
;; buffers is the next step, once the layout and interactions are
;; confirmed to feel right.
;;
;; Not loaded by `reviewer.el' itself -- treemacs is a much heavier
;; dependency than the mode's other optional integrations (posframe,
;; magit), so opt in explicitly with `(require 'reviewer-treemacs)'.

;;; Code:

(require 'reviewer)
(require 'treemacs)
(require 'treemacs-treelib)

(defgroup reviewer-treemacs nil
  "Treemacs-based tree/detail view for `reviewer-mode' annotations."
  :group 'reviewer)

(defcustom reviewer-treemacs-side 'right
  "Which side of the frame the tree/detail pane pair docks to."
  :type '(choice (const :tag "Left" left) (const :tag "Right" right))
  :group 'reviewer-treemacs)

(defcustom reviewer-treemacs-width 0.3
  "Width of the tree/detail pane pair.
An integer is an absolute width in columns; a float is a fraction of
the frame's width, e.g. the default 0.3 caps the pair at 30% of the
frame."
  :type '(choice (float :tag "Fraction of frame width")
                  (integer :tag "Columns"))
  :group 'reviewer-treemacs)

(defcustom reviewer-treemacs-summary-length 40
  "Number of characters a thread's tree label is truncated to.
Real `reviewer-mode' annotations have no separate title -- just note
text -- so the tree label is always a summary of the root note, never
the note in full."
  :type 'integer
  :group 'reviewer-treemacs)

(defcustom reviewer-treemacs-ret-moves-focus nil
  "Whether RET on a thread switches focus to its source location.
When nil (the default), RET jumps to the thread's source and shows it
there -- highlight, popup -- but leaves the tree window selected, so
n/p keep driving straight through a string of threads.  When non-nil,
RET instead switches focus there too, the same as \"o o\"."
  :type 'boolean
  :group 'reviewer-treemacs)

(defconst reviewer-treemacs--tree-buffer "*reviewer-tree*"
  "Buffer name for the treemacs tree pane.")

(defconst reviewer-treemacs--detail-buffer-default-name "*reviewer-detail*"
  "Detail pane buffer name used when no thread is selected yet.")

(defvar reviewer-treemacs--detail-buf nil
  "The detail pane's buffer object.
Its name changes to \"reviewer-thread-<key>\" as point moves between
threads -- see `reviewer-treemacs--show-detail' -- so hold onto this
object rather than a fixed name, e.g. via `get-buffer-window'.")

(defun reviewer-treemacs--detail-buffer ()
  "Return the detail pane's buffer, creating it if necessary."
  (unless (buffer-live-p reviewer-treemacs--detail-buf)
    (setq reviewer-treemacs--detail-buf
          (generate-new-buffer reviewer-treemacs--detail-buffer-default-name)))
  reviewer-treemacs--detail-buf)

;; --- placeholder data ------------------------------------------------------
;; Skeleton only: (FILE (LABEL :context CONTEXT :entries ENTRIES) ...)
;; tuples standing in for `reviewer-all-annotations' until this is wired
;; to real annotations.  ENTRIES is a list of (:author :time :text)
;; plists, oldest first -- the same shape as a root note plus its
;; `reviewer-annotation-replies'.  CONTEXT is a literal substring of
;; FILE to jump to on RET; nil if there's nothing worth searching for.
;; Once wired to real annotations, CONTEXT goes away and RET instead
;; jumps straight to the annotation's own overlay.

(defvar reviewer-treemacs--dummy-data
  '(("reviewer.el"
     ("Do we still need this require?"
      :context "(require 'color)"
      :entries ((:author "sreenivas" :time "09:58"
                 :text "Do we still need this direct require, or does color-hsl-to-rgb autoload it?")))
     ("Overlapping annotations?"
      :context "(defun reviewer--annotation-at (pos)"
      :entries ((:author "sreenivas" :time "10:02"
                 :text "Should this also handle multiple overlapping annotations under point?")
                (:author "reviewer-bot" :time "10:05"
                 :text "`overlays-at` just returns whichever the buffer happens to store first -- usually the most recently created one, but it's not guaranteed.")
                (:author "sreenivas" :time "10:11"
                 :text "Ok, not worth solving now -- annotations are single-user and session-local anyway.")))
     ("Nit: docstring wording"
      :context "Assigned once, when the annotation is created"
      :entries ((:author "reviewer-bot" :time "12:14"
                 :text "\"Assigned once, when the annotation is created\" reads a little awkwardly -- maybe \"Assigned when the annotation is first created\"?")))
     ("Should replies bump the timestamp?"
      :context "(defun reviewer-annotation-time (overlay)"
      :entries ((:author "sreenivas" :time "12:40"
                 :text "Right now `reviewer-annotation-time` only reflects the root note's creation time. Should a reply update some kind of \"last activity\" field?")
                (:author "reviewer-bot" :time "12:42"
                 :text "Could add a `reviewer-last-activity` overlay property, updated on every reply, separate from the immutable creation time. Keeps the two concerns distinct.")
                (:author "sreenivas" :time "12:43"
                 :text "Let's hold off until we actually sort threads by activity somewhere -- no consumer for it yet.")
                (:author "reviewer-bot" :time "12:44"
                 :text "Agreed, leaving as-is."))))
    ("README.org"
     ("Typo in setup section"
      :context "straight.el and use-package"
      :entries ((:author "sreenivas" :time "11:00"
                 :text "There's a typo here: \"recieve\" should be \"receive\".")))
     ("Missing use-package example for treemacs view"
      :context "(use-package reviewer"
      :entries ((:author "sreenivas" :time "11:15"
                 :text "Once reviewer-treemacs.el is real, we should add a use-package block here showing how to enable it alongside reviewer-mode."))))
    ("reviewer-treemacs.el"
     ("Dummy data placement"
      :context "placeholder data"
      :entries ((:author "sreenivas" :time "21:30"
                 :text "Just checking -- this dummy data block is clearly marked as throwaway, right? Don't want it surviving into the real wiring by accident.")
                (:author "reviewer-bot" :time "21:31"
                 :text "Yes, it's under the \"placeholder data\" section header and called out in the Commentary as the thing to replace next.")))
     ("Side window slot ordering"
      :context "(slot . 0)"
      :entries ((:author "sreenivas" :time "21:40"
                 :text "Is slot 0 always above slot 1 for a given side, regardless of side being left or right?")
                (:author "reviewer-bot" :time "21:41"
                 :text "Yes -- slot order is independent of which side the window is docked to; lower slot numbers are always closer to the frame edge, so slot 0 sits above slot 1 on both left and right.")))
     ("Very short note"
      :entries ((:author "sreenivas" :time "21:52" :text "lgtm"))))
    ("no-file-buffer"
     ("Annotation on a scratch buffer"
      :entries ((:author "sreenivas" :time "22:05"
                 :text "What should the tree show for annotations made in a buffer with no backing file, like *scratch*? Buffer name, presumably?"))))
    ("very/long/nested/path/to/some-module.el"
     ("Long file path wrapping"
      :entries ((:author "sreenivas" :time "22:10"
                 :text "This file label is going to be wider than the pane -- want to confirm long paths truncate or wrap sensibly instead of blowing out the tree width.")
                (:author "reviewer-bot" :time "22:11"
                 :text "Treemacs truncates with an ellipsis by default at the window edge rather than wrapping, so it should stay contained; worth eyeballing once real data is wired in.")))))
  "Placeholder tree data until this is wired to real annotations.")

;; --- faces ---------------------------------------------------------------

(defface reviewer-treemacs-file-face
  '((t :inherit font-lock-variable-name-face :weight bold))
  "Face used for file labels in the reviewer tree pane.
Deliberately a different color from `reviewer-treemacs-thread-face' so
files and threads are distinguishable by color alone, not just by
indentation and icon."
  :group 'reviewer-treemacs)

(defface reviewer-treemacs-thread-face
  '((t :inherit font-lock-doc-face))
  "Face used for a thread's label in the reviewer tree pane."
  :group 'reviewer-treemacs)

;; --- thread data accessors -------------------------------------------------
;; All read from the button's automatically-stored `:item' (the literal
;; (LABEL :context ... :entries ...) tuple from `reviewer-treemacs--dummy-data')
;; and `:path' (the key chain from the root down to this node) -- so a
;; reply appended in place via `reviewer-treemacs--append-reply' is
;; immediately reflected wherever these are called again, with no
;; separate refresh step.

(defun reviewer-treemacs--item (btn)
  "Return BTN's underlying `reviewer-treemacs--dummy-data' item.
`treemacs-button-get' only works when the current buffer is BTN's own
buffer, so this switches there first -- needed here since BTN is a
marker that outlives the tree buffer being selected, e.g. once control
reaches the reply pane or the detail pane."
  (treemacs-with-button-buffer btn (treemacs-button-get btn :item)))

(defun reviewer-treemacs--path (btn)
  "Return BTN's tree path.  See `reviewer-treemacs--item' for why."
  (treemacs-with-button-buffer btn (treemacs-button-get btn :path)))

(defun reviewer-treemacs--key (btn)
  "Return BTN's key.  See `reviewer-treemacs--item' for why."
  (treemacs-with-button-buffer btn (treemacs-button-get btn :key)))

(defun reviewer-treemacs--thread-entries (btn)
  "Return the replies list stored on thread node BTN's underlying item."
  (plist-get (cdr (reviewer-treemacs--item btn)) :entries))

(defun reviewer-treemacs--thread-context (btn)
  "Return the search string used to jump to thread node BTN's source, if any."
  (plist-get (cdr (reviewer-treemacs--item btn)) :context))

(defun reviewer-treemacs--thread-file (btn)
  "Return the file thread node BTN belongs to, from its tree path."
  (nth 1 (reviewer-treemacs--path btn)))

(defun reviewer-treemacs--format-thread (entries)
  "Format ENTRIES (a thread's plists) the same way the posframe view does.
Reuses `reviewer--format-thread-entry' so the two views stay visually
consistent: bold, per-author-colored name, muted timestamp, then text."
  (mapconcat (lambda (entry)
               (reviewer--format-thread-entry (plist-get entry :author)
                                               (plist-get entry :time)
                                               (plist-get entry :text)))
             entries "\n\n"))

(defun reviewer-treemacs--thread-detail (btn)
  "Format thread node BTN's full conversation for the detail pane."
  (reviewer-treemacs--format-thread (reviewer-treemacs--thread-entries btn)))

(defun reviewer-treemacs--summarize (text)
  "Truncate TEXT to `reviewer-treemacs-summary-length' characters.
Collapses newlines to spaces first, since a summary is meant to render
on a single tree line, then appends an ellipsis if still truncated."
  (let ((flat (replace-regexp-in-string "\n+" " " text)))
    (if (> (length flat) reviewer-treemacs-summary-length)
        (concat (substring flat 0 reviewer-treemacs-summary-length) "…")
      flat)))

(defun reviewer-treemacs--item-summary (item)
  "Return the tree label for thread ITEM: its root note, summarized.
Takes the raw ITEM rather than a button, since node-type label forms
only have that -- see the node type definitions below."
  (reviewer-treemacs--summarize
   (plist-get (car (plist-get (cdr item) :entries)) :text)))

;; --- detail pane -------------------------------------------------------

(defconst reviewer-treemacs--placeholder-text
  "Select a thread to see it here."
  "Detail pane text shown when point isn't on a thread node.")

(defvar-local reviewer-treemacs--last-preview-key nil
  "Key of the node last previewed in the detail pane by cursor movement.")

(defun reviewer-treemacs--show-detail (text &optional key)
  "Show TEXT in the detail pane, named after thread KEY.
Renames the pane to \"reviewer-thread-<KEY>\" so it's identifiable on
its own -- a stand-in for the real `reviewer-annotation-thread-id'
once this is wired to real annotations.  With no KEY (nothing selected
yet), the pane keeps its generic default name."
  (with-current-buffer (reviewer-treemacs--detail-buffer)
    (rename-buffer (if key (format "reviewer-thread-%s" key)
                      reviewer-treemacs--detail-buffer-default-name)
                    t)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert text)
      (goto-char (point-min)))
    (special-mode)
    ;; Set after `special-mode' since major modes wipe non-permanent
    ;; buffer-local variables via `kill-all-local-variables'.
    (setq truncate-lines nil)
    (reviewer-treemacs--local-keymap (current-local-map)
                                      '(("q" . reviewer-treemacs-toggle)
                                        ("C-g" . reviewer-treemacs-toggle)))))

(defun reviewer-treemacs--preview-at-point ()
  "Preview the thread at point in the detail pane as the cursor moves.
Runs on `post-command-hook' in the tree buffer so any navigation --
n/p, arrow keys, a mouse click -- updates the detail pane immediately,
without waiting for RET."
  (let* ((btn (treemacs-current-button))
         (key (and btn (treemacs-button-get btn :key))))
    (unless (equal key reviewer-treemacs--last-preview-key)
      (setq reviewer-treemacs--last-preview-key key)
      (if (and btn (treemacs-button-get btn :leaf))
          (reviewer-treemacs--show-detail (reviewer-treemacs--thread-detail btn) key)
        (reviewer-treemacs--show-detail reviewer-treemacs--placeholder-text)))))

;; --- navigation ----------------------------------------------------------

(defun reviewer-treemacs--move-to-leaf (move-fn)
  "Call MOVE-FN, then keep calling it while point rests on a file node.
File nodes are just group headers in this tree -- there's nothing to
preview or act on for one -- so n/p should never leave point sitting
on one; skip straight through to the next thread in that direction.
Stops as soon as MOVE-FN stops making progress, so a file node with no
threads under it (or the top/bottom of the tree) doesn't loop forever."
  (let ((pos (point)))
    (funcall move-fn 1)
    (while (and (/= (point) pos)
                (let ((btn (treemacs-current-button)))
                  (and btn (not (treemacs-button-get btn :leaf)))))
      (setq pos (point))
      (funcall move-fn 1))))

(defun reviewer-treemacs-next-line ()
  "Move to the next thread in the tree, skipping over file nodes."
  (interactive)
  (reviewer-treemacs--move-to-leaf #'treemacs-next-line))

(defun reviewer-treemacs-previous-line ()
  "Move to the previous thread in the tree, skipping over file nodes."
  (interactive)
  (reviewer-treemacs--move-to-leaf #'treemacs-previous-line))

;; --- jump to source ------------------------------------------------------

(defvar reviewer-treemacs--preview-overlay nil
  "Overlay standing in for a real `reviewer-mode' annotation at the
last-visited thread's context span.  Only one is ever live at a time,
moved onto the newly visited span on each RET rather than accumulating
one per visit.")

(defun reviewer-treemacs--highlight-context (btn start end)
  "Turn START..END in the current buffer into a real annotation overlay
carrying thread node BTN's data.
Giving it the same `reviewer-note' etc. properties a real annotation
has -- not just `reviewer-highlight-face' -- is what makes ordinary
`reviewer.el' commands (`reviewer-show-annotation-at-point',
`reviewer-delete-annotation-at-point', ...) recognize and work on it
afterwards, instead of reporting \"No annotation at point\"."
  (unless (overlayp reviewer-treemacs--preview-overlay)
    (setq reviewer-treemacs--preview-overlay (make-overlay start end)))
  (move-overlay reviewer-treemacs--preview-overlay start end (current-buffer))
  (let* ((entries (reviewer-treemacs--thread-entries btn))
         (root (car entries)))
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-note (plist-get root :text))
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-author (plist-get root :author))
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-time (plist-get root :time))
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-status "open")
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-thread-id (reviewer-treemacs--key btn))
    (overlay-put reviewer-treemacs--preview-overlay 'reviewer-replies (cdr entries))
    (overlay-put reviewer-treemacs--preview-overlay 'face 'reviewer-highlight-face)))

(defun reviewer-treemacs--main-window ()
  "Return a window to open a visited annotation's file in, or nil.
The most-recently-used window that isn't dedicated -- i.e. not one of
the tree/detail/reply side windows -- so RET reuses whatever \"main\"
window the user was last working in instead of leaving the choice to
`pop-to-buffer's own heuristics, which -- combined with this user's
`display-buffer-alist' -- were splitting a new window inconsistently."
  (seq-find (lambda (w) (not (window-dedicated-p w)))
            (sort (window-list nil 'no-minibuf)
                  (lambda (a b) (> (window-use-time a) (window-use-time b))))))

(defun reviewer-treemacs--visit-file (path)
  "Visit PATH in `reviewer-treemacs--main-window', or split if none exists."
  (let ((buf (find-file-noselect path))
        (window (reviewer-treemacs--main-window)))
    (if window
        (progn (select-window window) (switch-to-buffer buf))
      (pop-to-buffer buf))))

(defun reviewer-treemacs--visit-file-split (path side)
  "Visit PATH in a new window, splitting on SIDE (`right' or `below').
Splits `reviewer-treemacs--main-window' when there is one, so the new
window lands next to the user's actual working window rather than
next to the tree/detail pane; falls back to `reviewer-treemacs--visit-file'
when there's no other window to split."
  (let ((window (reviewer-treemacs--main-window)))
    (if (not window)
        (reviewer-treemacs--visit-file path)
      (select-window (split-window window nil side))
      (switch-to-buffer (find-file-noselect path)))))

(defun reviewer-treemacs--jump-to-context (btn &optional visit-fn)
  "Jump to thread node BTN's source location and highlight it there.
VISIT-FN opens the resolved file path, defaulting to
`reviewer-treemacs--visit-file'; callers pass an alternative to open it
elsewhere instead, e.g. a fresh split.

Best-effort stand-in for real annotation jumping: the file is resolved
relative to `default-directory' and the context is just a literal
search string, since the dummy data has no real buffer/position to
jump to.  Once wired to `reviewer-all-annotations', this instead jumps
straight to the annotation's own overlay, which already carries its
own highlight and position."
  (let* ((file (reviewer-treemacs--thread-file btn))
         (context (reviewer-treemacs--thread-context btn))
         (path (expand-file-name file default-directory)))
    (unless (file-exists-p path)
      (user-error "%s doesn't exist -- dummy data only" file))
    (funcall (or visit-fn #'reviewer-treemacs--visit-file) path)
    (unless reviewer-mode (reviewer-mode 1))
    (goto-char (point-min))
    (if (and context (search-forward context nil t))
        (progn
          (goto-char (match-beginning 0))
          (reviewer-treemacs--highlight-context btn (match-beginning 0) (match-end 0))
          (reviewer-show-annotation-at-point))
      (reviewer--display-annotation (reviewer-treemacs--thread-detail btn))
      (add-hook 'pre-command-hook #'reviewer--hide-annotation-display-once nil t))))

(defun reviewer-treemacs--visit-annotation (&optional _arg)
  "Jump to the source location of the thread node at point, switching
focus to it; an \"o o\" binding."
  (interactive)
  (when-let* ((btn (treemacs-current-button)))
    (reviewer-treemacs--jump-to-context btn)))

(defun reviewer-treemacs--peek-annotation (&optional _arg)
  "Show the source location of the thread node at point, without
leaving the tree window selected; a `:ret-action'.
Runs the same jump as `reviewer-treemacs--visit-annotation' -- visit
the file, highlight the context span, pop up the annotation -- but
wrapped in `save-selected-window' so the tree stays selected
afterward and n/p keep driving straight through a string of threads."
  (interactive)
  (when-let* ((btn (treemacs-current-button)))
    (save-selected-window
      (reviewer-treemacs--jump-to-context btn))))

(defun reviewer-treemacs--ret-annotation (&optional arg)
  "Jump to the source location of the thread node at point; a `:ret-action'.
Dispatches to `reviewer-treemacs--visit-annotation' or
`reviewer-treemacs--peek-annotation' depending on
`reviewer-treemacs-ret-moves-focus'."
  (interactive)
  (if reviewer-treemacs-ret-moves-focus
      (reviewer-treemacs--visit-annotation arg)
    (reviewer-treemacs--peek-annotation arg)))

(defun reviewer-treemacs--visit-annotation-btn (btn)
  "Jump to the source location of BTN; a `:visit-action'."
  (reviewer-treemacs--jump-to-context btn))

(defun reviewer-treemacs--thread-at-point ()
  "Return the thread node button at point, or signal a `user-error'."
  (let ((btn (treemacs-current-button)))
    (unless (and btn (treemacs-button-get btn :leaf))
      (user-error "No thread at point"))
    btn))

(defun reviewer-treemacs-open-vertical-split ()
  "Jump to the thread at point's source, opened in a new vertical split."
  (interactive)
  (reviewer-treemacs--jump-to-context
   (reviewer-treemacs--thread-at-point)
   (lambda (path) (reviewer-treemacs--visit-file-split path 'right))))

(defun reviewer-treemacs-open-horizontal-split ()
  "Jump to the thread at point's source, opened in a new horizontal split."
  (interactive)
  (reviewer-treemacs--jump-to-context
   (reviewer-treemacs--thread-at-point)
   (lambda (path) (reviewer-treemacs--visit-file-split path 'below))))

(defun reviewer-treemacs-open-and-close ()
  "Jump to the thread at point's source, then close the tree/detail pane."
  (interactive)
  (reviewer-treemacs--jump-to-context (reviewer-treemacs--thread-at-point))
  (reviewer-treemacs--close))

;; --- reply pane ------------------------------------------------------------

(defconst reviewer-treemacs--reply-buffer "*reviewer-reply*"
  "Buffer used to compose a reply to a thread in the tree pane.")

(defvar-local reviewer-treemacs--reply-target nil
  "The treemacs button `reviewer-treemacs-reply-finish' appends this reply to.")

(defvar-local reviewer-treemacs--reply-saved-heights nil
  "Tree/detail window heights captured before this reply pane opened.
An alist of (WINDOW . HEIGHT); see `reviewer-treemacs--save-heights'.
Restored once the reply pane closes, since inserting and removing a
third window in the same side column otherwise leaves Emacs's own
space redistribution in place rather than reverting it.")

(defun reviewer-treemacs--save-heights ()
  "Return an alist of (WINDOW . HEIGHT) for the tree/detail windows."
  (mapcar (lambda (window) (cons window (window-height window)))
          (reviewer-treemacs--windows)))

(defun reviewer-treemacs--restore-heights (saved)
  "Resize each window in SAVED back to its recorded height.
SAVED is an alist as returned by `reviewer-treemacs--save-heights'."
  (dolist (entry saved)
    (when (window-live-p (car entry))
      (window-resize (car entry) (- (cdr entry) (window-height (car entry))) nil t))))

(defun reviewer-treemacs--close-reply-window ()
  "Close the reply pane, if open, restoring the heights it disturbed."
  (when-let* ((buf (get-buffer reviewer-treemacs--reply-buffer)))
    (let ((saved (buffer-local-value 'reviewer-treemacs--reply-saved-heights buf))
          (window (get-buffer-window buf)))
      (when window (delete-window window))
      (kill-buffer buf)
      (reviewer-treemacs--restore-heights saved))))

(defun reviewer-treemacs--append-reply (btn text)
  "Append TEXT as a reply, from the current user, to thread node BTN.
Mutates BTN's `:item' in place -- see the note on thread data accessors
above -- so the detail pane can be refreshed by simply re-reading it."
  (let ((entries-cell (cdr (reviewer-treemacs--item btn))))
    (plist-put entries-cell :entries
               (append (plist-get entries-cell :entries)
                       (list (list :author (user-login-name)
                                   :time (format-time-string "%H:%M")
                                   :text text))))))

(defun reviewer-treemacs-reply-finish ()
  "Append this buffer's text as a reply, then close the reply pane."
  (interactive)
  (let ((text (string-trim (buffer-string)))
        (btn reviewer-treemacs--reply-target))
    (reviewer-treemacs--close-reply-window)
    (unless (string-empty-p text)
      (reviewer-treemacs--append-reply btn text)
      (reviewer-treemacs--show-detail (reviewer-treemacs--thread-detail btn)
                                       (reviewer-treemacs--key btn)))))

(defun reviewer-treemacs-reply-abort ()
  "Abandon this reply without appending anything."
  (interactive)
  (reviewer-treemacs--close-reply-window))

(defvar reviewer-treemacs-reply-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'reviewer-treemacs-reply-finish)
    (define-key map (kbd "C-c C-k") #'reviewer-treemacs-reply-abort)
    map)
  "Keymap for `reviewer-treemacs-reply-mode'.")

(define-derived-mode reviewer-treemacs-reply-mode text-mode "Reviewer-Reply"
  "Major mode for composing a reply to a thread in the reviewer tree pane.
\\{reviewer-treemacs-reply-mode-map}"
  (setq header-line-format
        (substitute-command-keys
         (concat "Reply to thread.  "
                 "\\[reviewer-treemacs-reply-finish] to send, "
                 "\\[reviewer-treemacs-reply-abort] to cancel."))))

(defun reviewer-treemacs-reply-to-thread-at-point ()
  "Open a reply pane, stacked below the detail pane, for the thread at point."
  (interactive)
  (let ((btn (treemacs-current-button)))
    (unless (and btn (treemacs-button-get btn :leaf))
      (user-error "No thread at point"))
    (let ((saved (reviewer-treemacs--save-heights)))
      (select-window
       (display-buffer-in-side-window
        (get-buffer-create reviewer-treemacs--reply-buffer)
        `((side . ,reviewer-treemacs-side) (slot . 2)
          (window-width . ,(reviewer-treemacs--resolved-width))
          (window-height . 8))))
      (reviewer-treemacs-reply-mode)
      (erase-buffer)
      (setq reviewer-treemacs--reply-target btn)
      (setq reviewer-treemacs--reply-saved-heights saved))))

;; --- node types --------------------------------------------------------

(treemacs-define-leaf-node-type reviewer-treemacs-thread
  :icon "‣ "
  :label (propertize (reviewer-treemacs--item-summary item) 'face 'reviewer-treemacs-thread-face)
  :key (car item)
  :ret-action #'reviewer-treemacs--ret-annotation
  :visit-action #'reviewer-treemacs--visit-annotation-btn)

(treemacs-define-expandable-node-type reviewer-treemacs-file
  :closed-icon (propertize "▸ " 'face 'reviewer-treemacs-file-face)
  :open-icon (propertize "▾ " 'face 'reviewer-treemacs-file-face)
  :label (propertize (car item) 'face 'reviewer-treemacs-file-face)
  :key (car item)
  :children (cdr item)
  :child-type 'reviewer-treemacs-thread)

(treemacs-define-variadic-entry-node-type reviewer-treemacs-root
  :key 'reviewer-treemacs-root
  :children reviewer-treemacs--dummy-data
  :child-type 'reviewer-treemacs-file)

;; --- locked side-window pair --------------------------------------------

(defun reviewer-treemacs--lock-window (window)
  "Mark WINDOW dedicated, protected from `delete-other-windows', and
its height preserved against automatic resizing.
The height preservation matters once the reply pane opens as a third,
temporary window stacked below WINDOW in the same side column --
without it, Emacs redistributes space across all three and doesn't
restore the original split when the reply pane closes."
  (set-window-dedicated-p window t)
  (set-window-parameter window 'no-delete-other-windows t)
  (window-preserve-size window nil t)
  window)

(defun reviewer-treemacs--unlock-window (window)
  "Undo `reviewer-treemacs--lock-window' on WINDOW before deleting it."
  (set-window-parameter window 'no-delete-other-windows nil)
  (set-window-dedicated-p window nil))

(defun reviewer-treemacs--windows ()
  "Return the live windows currently showing the tree/detail pane pair."
  (delq nil (list (get-buffer-window reviewer-treemacs--tree-buffer)
                   (and (buffer-live-p reviewer-treemacs--detail-buf)
                        (get-buffer-window reviewer-treemacs--detail-buf)))))

(defun reviewer-treemacs--local-keymap (parent-map bindings)
  "Install a local keymap over PARENT-MAP with BINDINGS added.
BINDINGS is an alist of (KEY . COMMAND); KEY is passed through `kbd'.
Buffer-local, so it doesn't touch PARENT-MAP itself -- e.g.
`treemacs-mode-map' or `special-mode-map' -- and affect unrelated
buffers."
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map parent-map)
    (dolist (binding bindings)
      (define-key map (kbd (car binding)) (cdr binding)))
    (use-local-map map)))

(defun reviewer-treemacs--resolved-width ()
  "Resolve `reviewer-treemacs-width' to an absolute column count.
Side windows don't reliably honor a float `window-width' entry -- the
resize Emacs performs after the initial split silently no-ops for
side-window trees -- so the fraction is turned into columns here and
handed to `display-buffer-in-side-window' as a plain integer instead."
  (if (floatp reviewer-treemacs-width)
      (round (* reviewer-treemacs-width (frame-width)))
    reviewer-treemacs-width))

(defun reviewer-treemacs--open ()
  "Open the locked tree/detail pane pair, tree above detail."
  (let* ((side reviewer-treemacs-side)
         (width (reviewer-treemacs--resolved-width))
         (tree-window (display-buffer-in-side-window
                       (get-buffer-create reviewer-treemacs--tree-buffer)
                       `((side . ,side) (slot . 0)
                         (window-width . ,width))))
         (detail-window (display-buffer-in-side-window
                         (reviewer-treemacs--detail-buffer)
                         `((side . ,side) (slot . 1)
                           (window-width . ,width)))))
    (reviewer-treemacs--lock-window tree-window)
    (reviewer-treemacs--lock-window detail-window)
    (reviewer-treemacs--show-detail reviewer-treemacs--placeholder-text)
    (select-window tree-window)
    (treemacs-initialize reviewer-treemacs-root
      :with-expand-depth 1)
    (reviewer-treemacs--local-keymap treemacs-mode-map
                                      `(("q" . reviewer-treemacs-toggle)
                                        ("C-g" . reviewer-treemacs-toggle)
                                        ("r" . reviewer-treemacs-reply-to-thread-at-point)
                                        ("n" . reviewer-treemacs-next-line)
                                        ("p" . reviewer-treemacs-previous-line)
                                        ("o o" . reviewer-treemacs--visit-annotation)
                                        ("o v" . reviewer-treemacs-open-vertical-split)
                                        ("o h" . reviewer-treemacs-open-horizontal-split)
                                        ("o c" . reviewer-treemacs-open-and-close)))
    (add-hook 'post-command-hook #'reviewer-treemacs--preview-at-point nil t)))

(defun reviewer-treemacs--close ()
  "Close the tree/detail pane pair, killing their buffers.
Also closes the reply pane, if open, and clears the last visited
thread's highlight."
  (reviewer-treemacs--close-reply-window)
  (dolist (window (reviewer-treemacs--windows))
    (let ((buf (window-buffer window)))
      (reviewer-treemacs--unlock-window window)
      (delete-window window)
      (kill-buffer buf)))
  (setq reviewer-treemacs--detail-buf nil)
  (when (overlayp reviewer-treemacs--preview-overlay)
    (delete-overlay reviewer-treemacs--preview-overlay))
  (setq reviewer-treemacs--preview-overlay nil))

;;;###autoload
(defun reviewer-treemacs-toggle ()
  "Toggle the locked reviewer tree/detail pane pair."
  (interactive)
  (if (reviewer-treemacs--windows)
      (reviewer-treemacs--close)
    (reviewer-treemacs--open)))

;; Appended to `reviewer.el's transient rather than defined alongside
;; it, since that file shouldn't have to require treemacs just to know
;; this suffix exists -- this one opts in like everything else here.
(transient-append-suffix 'reviewer-transient "e"
  '("t" "toggle tree/detail view" reviewer-treemacs-toggle))

(provide 'reviewer-treemacs)
;;; reviewer-treemacs.el ends here
