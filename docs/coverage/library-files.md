# Coverage: Library files (Files with the Vault, Notes)

Inventory sections: 2.2 Notes, 2.5 Library (sections, Files, document editor, Google, Drive, Vault, Map), phone gaps (agent part 7).
All on sample data behind `VaultStore`, `NotesStore`, `LibraryDocumentsStore`, `ChatDocsStore`, `UploadsStore` and `DriveStore` (each behind a small protocol), so the desktop data can replace it.
Code: `KairosAgents/Features/Library/Files/`. Pictures: `Tools/screens/library-files.txt`.

## Library sections

| Feature | Where |
|---|---|
| Library sections, phone chips, section descriptions | The shell's glass switch (Files, Notes, ...). Files holds the Vault first, then chat documents, Drive, uploads, documents (`LibraryFilesSection`). Designs live in Make (Make team). |
| Section remembered, deep links | Shell `router.librarySection`; inside Files each place opens as a full-screen cover (`FilesCover`), and the Vault opens on Home, a note, the Map or today's note (`VaultStart`). |
| Phone "All" overview (Vault card with mini map, Recent, upload) | `LibraryFilesSection`: Vault card with `VaultMiniMap`, Browse/Map/Today, "Recent in the vault", places, documents. Search is the shell's search sheet. |
| Leave guard | Vault editor: "Discard note edits?" on back, Map, and Done. Document editor: discard prompt and no swipe-down while dirty. |
| Shared empty states and confirms | `FilesEmpty`, `confirmationDialog` everywhere a thing is deleted or discarded. |

## Files: documents and chat files (`Documents/`)

| Feature | Where |
|---|---|
| Combined search | `ChatDocumentsScreen` search field. |
| Collapsible Documents and Files by chat with counts | `ChatDocumentsScreen`. |
| New document, Import from file (.md, .txt) with status and toasts | `ChatDocumentsScreen` (`.fileImporter`), "New document" also on the Files section. |
| Document cards with updated date or match snippet | `ChatDocsDocumentRow`. |
| Chat file groups, rows with type, size, origin, "No longer available" | `ChatDocsGroupCard`, `ChatDocsFileRow`; a file opens the shared `DocumentViewer`; long-press a group to open its chat. |
| Empty states with "Create a document" and "Open chats" | `ChatDocumentsScreen` (`files-chatdocs-empty`). |
| Uploads | `UploadsScreen`: real file picker, sort, search, rename, share, delete. |

## Document editor

| Feature | Where |
|---|---|
| Title, content, Save, Saving and Saved states, Delete with confirm, discard prompt, phone back header | `LibraryDocumentEditor`. Ctrl/Cmd+S is a keyboard shortcut; the phone has the Save button. |

## Shared library between accounts

Lives in the Tool Store ("Shared library" filter) and on each skill, bot or automation: owned by the You and Bots areas, not here.

## Google account and Drive (`Drive/`)

| Feature | Where |
|---|---|
| Setup card, client ID, connect, admin restriction | Needs the computer running Kairos: the accounts sheet says so in one line. Client ID setup is a desktop-only admin step. |
| Multiple accounts, add another, sending status, disconnect, phone account card | Account card and "Google accounts" sheet (`drive-accounts`). |
| Drive views, storage, search, type filter, grid and list, refresh | `DriveBrowser` (chips inline instead of an options sheet). |
| Quick access, folder navigation with breadcrumb, file rows and cards, grouped Folders and Files | `DriveBrowser`, `DriveRows` (`drive-home`, `drive-folder`). |
| Details vs open on touch | Tap opens; details from the row menu or the preview. |
| Load more, partial, error states | Empty state "No matching Google files."; load-more and partial results need the real API. |
| New menu: folder, upload (25 MB cap), sheet, form, naming prompt | "New in Drive" sheet and naming alert (`drive-new`). |
| Drag-and-drop upload | Desktop only; the phone uses Upload files. |
| Selection checkboxes and toolbar (Move, Copy, Star, Trash or Restore) | Select mode (`drive-select`). Shift and Ctrl clicks are replaced by checkboxes. |
| Right-click menu | Long-press `contextMenu` on every row (phone gap closed). |
| Details panel, revisions, destination picker, sharing and permissions | `DriveDetails` (`drive-details`, `drive-share`), "Move to folder" sheet. "Open in Google" needs a real file link from the desktop. |
| Preview | `DrivePreview` (`drive-preview`). PDF rendering of real files needs the desktop. |
| Sheets editor | `DriveSheetEditor` with 44-point cells and sideways scroll (phone gap closed). |
| Forms editor | `DriveFormEditor`. |

## Vault (`Vault/`)

| Feature | Where |
|---|---|
| One shared store, pinned notes, recent notes, folder ordering and dated folders, orphans and missing properties | `VaultStore` (`VaultModels.swift`). Pins and recents are in memory until the desktop syncs them. |
| Search vault: Names and In note text with snippets, Escape clears, Enter opens | `VaultHomeView` search (`vault-search`). |
| Folder tree with counts, Index tags, month headings, Empty folder, Pinned and Recent groups | `VaultTree`, `VaultTreeGroup` on Vault Home; `VaultFolderView` (`vault-folder`). Long-press a folder or note for its menu. |
| Home pill, Map pill, refresh, today's note button, counts | Header: Map button, options menu (Today's note, Reload the vault), "N notes · M folders · K links". |
| Vault Home: Today card, pinned card, daily notes month strip, recently changed, needs attention, browse by property | `VaultHomeView` (`vault-home`), `VaultListView` (`vault-list`). After creating today's note, the folder index prompt shows the one line to add, with Add line and Not now, and a version check (`vault-today`). |
| Open a note, note header with breadcrumb, meta, properties, Links pill | `VaultNoteView` (`vault-note`). |
| Rendered note: headings, lists, checkboxes (tickable), code, tables, quotes, callouts, wikilinks, embeds, attachments, hidden frontmatter and repeated title | `VaultMarkdown` and `VaultMarkdownView`. Remote images are not loaded in the sample. |
| Edit, Ask Kairos, Pin, more menu (Copy path, Copy wikilink, History, Show on map) | `VaultNoteView`. Ask Kairos closes the Vault and starts a new chat; attaching the note as a chip needs a hook in the chat area. "Open in Obsidian" is desktop only. |
| Phone note page with back, title that fades in, Note options | `VaultNoteView` header. |
| About this note rail: properties, Linked from, Links out, Related by keywords, local graph, History | `VaultLinksSheet` (`vault-links`), `VaultLocalGraph`, `VaultChangeSheet` with diff and restore (`vault-history`). |
| Editor: Write and Preview, `[[` suggestions, Save and Done, status text | `VaultEditor` (`vault-write`, `vault-preview`), with Link and Checkbox keys above the keyboard. |
| Version conflict dialog, properties removal guard | `VaultEditor` (`vault-conflict`). |
| Map canvas: circles and triangles, size by backlinks, colour by project, arrow ticks, selection highlight, labels with zoom, settle and drift (off for Reduce Motion) | `VaultMapView` (`vault-map`). |
| Pan, drag nodes, zoom, select | Drag to pan, drag a node to move it, pinch to zoom 0.15x to 3x, plus zoom buttons (phone gap closed). |
| Map search, Fit view, All folders, Browse pill, filters and project legend, focus mode with depth and Whole vault, counts and hint | `VaultMapView` (`vault-focus`). |
| Phone peek sheet | `VaultPeekSheet` (`vault-peek`). |

## Notes (`LibraryNotesSection.swift`, `Notes/`)

| Feature | Where |
|---|---|
| Capture with optional due time, Add note | `NotesCaptureCard` (`notes-composing`). |
| Finished and Due this week tiles | `NotesStatTile`. |
| Count and Clear finished with confirm | Section header row. |
| Sort (Saved order, Due time, A-Z), search | Sort menu and search field. |
| Note cards: complete, show more, short due label, overdue colour, delete with confirm, pinned first | `NotesCard`, long-press menu (Edit, Pin, Due time, Details, Delete). |
| Note details sheet | `NotesDetailsSheet` (`notes-details`). |
| Empty state | `notes-empty`. |
