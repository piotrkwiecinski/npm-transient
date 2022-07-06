;;; npm-mode.el --- minor mode for working with npm projects

;; Version: 0.6.0
;; Author: Allen Gooch <allen.gooch@gmail.com>
;; Maintainer: Lucien Cartier-Tilet <lucien@phundrak.com>
;; Url: https://github.com/Phundrak/npm-mode
;; Keywords: convenience, project, javascript, node, npm
;; Package-Requires: ((emacs "25.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; This package allows you to easily work with npm projects.  It provides
;; a minor mode for convenient interactive use of API with a
;; mode-specific command keymap.
;;
;; | command                       | keymap       | description                         |
;; |-------------------------------|--------------|-------------------------------------|
;; | npm-mode-npm-init             | <kbd>n</kbd> | Initialize new project              |
;; | npm-mode-npm-install          | <kbd>i</kbd> | Install all project dependencies    |
;; | npm-mode-npm-install-save     | <kbd>s</kbd> | Add new project dependency          |
;; | npm-mode-npm-install-save-dev | <kbd>d</kbd> | Add new project dev dependency      |
;; | npm-mode-npm-uninstall        | <kbd>u</kbd> | Remove project dependency           |
;; | npm-mode-npm-list             | <kbd>l</kbd> | List installed project dependencies |
;; | npm-mode-npm-run              | <kbd>r</kbd> | Run project script                  |
;; | npm-mode-visit-project-file   | <kbd>v</kbd> | Visit project package.json file     |
;; |                               | <kbd>?</kbd> | Display keymap commands             |

;;; Credit:

;; This package began as a fork of the emacsnpm package, and its
;; repository history has been preserved.  Many thanks to Alex
;; for his contribution.
;; https://github.com/AlexChesters/emacs-npm repo.

;;; Code:

(require 'json)
(require 'transient)

(defgroup npm-mode nil
  "Customization group for `npm-mode'."
  :prefix "npm-mode-"
  :group 'tools
  :group 'convenience
  :link '(url-link :tag "Github" "https://github.com/Phundrak/eshell-info-banner.el"))

(defcustom npm-mode-comint t
  "Colorize NPM’s buffer.
See the argument COMINT in function `compile'."
  :group 'npm-mode
  :type 'boolean
  :safe #'booleanp)

(defcustom npm-mode-command-prefix "C-c n"
  "Prefix for npm-mode."
  :group 'npm-mode
  :type 'string)

(defvar npm-mode--project-file-name "package.json"
  "The name of npm project files.")

(defvar npm-mode--modeline-name " npm"
  "Name of npm mode modeline name.")

(defun npm-mode--ensure-npm-module ()
  "Assert the current directory is inside an npm module."
  (npm-mode--project-file))

(defun npm-mode--project-file ()
  "Return path to the project file, or nil.
If project file exists in the current working directory, or a
parent directory recursively, return its path.  Otherwise, return
nil."
  (let ((dir (locate-dominating-file default-directory npm-mode--project-file-name)))
    (unless dir
      (error (concat "Error: cannot find " npm-mode--project-file-name)))
    (concat dir npm-mode--project-file-name)))

(defun npm-mode--get-project-property (prop &optional suffix)
  "Get the given PROP from the current project file.
If SUFFIX is non-nil, then it gets suffixed to the car of each
value if the result is a list."
  (let* ((project-file (npm-mode--project-file))
         (json-object-type 'hash-table)
         (json-contents (with-temp-buffer
                          (insert-file-contents project-file)
                          (buffer-string)))
         (json-hash (json-read-from-string json-contents))
         (value (gethash prop json-hash))
         values)
    (if (not (hash-table-p value))
        value
      (maphash (lambda (key value)
                 (setq values
                       (append values
                               `((,(if suffix (concat key " " suffix) key) . ,key)))))
               value)
      values)))

(defun npm-mode--get-project-scripts ()
  "Get a list of project scripts."
  (npm-mode--get-project-property "scripts"))

(defun npm-mode--get-project-dependencies ()
  "Get a list of project dependencies."
  (append (npm-mode--get-project-property "dependencies")
          (npm-mode--get-project-property "devDependencies" "(dev)")
          (npm-mode--get-project-property "peerDependencies" "(peer)")
          (npm-mode--get-project-property "bundledDependencies" "(bundled)")
          (npm-mode--get-project-property "optionalDependencies" "(optional)")))

(defun npm-mode--exec-process (cmd)
  "Execute a process running CMD."
  (let ((compilation-buffer-name-function
         (lambda (mode)
           (format "*npm:%s - %s*"
                   (npm-mode--get-project-property "name") cmd))))
    (message (concat "Running " cmd))
    (compile cmd npm-mode-comint)))

(defun npm-mode-npm-clean ()
  "Run the \\='npm list\\=' command."
  (interactive)
  (let ((dir (concat (file-name-directory (npm-mode--ensure-npm-module)) "node_modules")))
    (if (file-directory-p dir)
      (when (yes-or-no-p (format "Are you sure you wish to delete %s?" dir))
        (npm-mode--exec-process (format "rm -rf %s" dir)))
      (message (format "%s has already been cleaned" dir)))))

(defun npm-mode-npm-init ()
  "Run the \\='npm init\\=' command."
  (interactive)
  (npm-mode--exec-process "npm init"))

(defun npm-mode-npm-install ()
  "Run the \\='npm install\\=' command."
  (interactive)
  (npm-mode--exec-process "npm install"))

;;; Installing Dependencies

(defun npm-mode-npm-install-save (dep &optional dest)
  "Run the \\='npm install --save\\=' command for DEP.
If DEST is non-nil or if it has the value \\='regular, then
DEP is installed as a regular dependency. Otherwise, it is
installed as one of the following dependencies (and valid
values):
- dev
- peer
- bundled
- optional
DEST can be a string or a symbol."
  (interactive (list (read-string "Enter package name: ")
                     (completing-read "Type of dependency: "
                                      '(regular
                                        dev
                                        peer
                                        bundle
                                        optional))))
  (npm-mode--exec-process (format "npm install %s --save%s"
                                  dep
                                  (if (or (not dest)
                                          (string= dest "regular"))
                                      ""
                                    (format "-%s" dest)))))

(defun npm-mode-npm-install-save-regular (dep)
  "Run the \\='npm install --save\\=' command for DEP."
  (interactive "sEnter package name: ")
  (npm-mode-npm-install-save dep))

(defun npm-mode-npm-install-save-dev (dep)
  "Run the \\='npm install --save-dev\\=' command for DEP."
  (interactive "sEnter package name: ")
  (npm-mode-npm-install-save dep 'dev))

(defun npm-mode-npm-install-save-peer (dep)
  "Run the \\='npm install --save-peer\\=' command for DEP."
  (interactive "sEnter package name: ")
  (npm-mode-npm-install-save dep 'peer))

(defun npm-mode-npm-install-save-bundle (dep)
  "Run the \\='npm install --save-bundle\\=' command for DEP."
  (interactive "sEnter package name: ")
  (npm-mode-npm-install-save dep 'bundle))

(defun npm-mode-npm-install-save-optional (dep)
  "Run the \\='npm install --save-optional\\=' command for DEP."
  (interactive "sEnter package name: ")
  (npm-mode-npm-install-save dep 'optional))


(defun npm-mode-npm-uninstall ()
  "Run the \\='npm uninstall\\=' command."
  (interactive)
  (let* ((deps (npm-mode--get-project-dependencies))
         (dep-read (completing-read "Uninstall dependency: " deps))
         (dep (cdr (assoc-string dep-read deps))))
    (npm-mode--exec-process (format "npm uninstall %s" dep))))

(defun npm-mode-npm-list ()
  "Run the \\='npm list\\=' command."
  (interactive)
  (npm-mode--exec-process "npm list --depth=0"))

(defun npm-run--read-command ()
  "Read command from user."
  (completing-read "Run script: " (npm-mode--get-project-scripts)))

(defun npm-mode-npm-run (script)
  "Run the \\='npm run\\=' command on a project SCRIPT."
  (interactive
   (list (npm-run--read-command)))
  (npm-mode--exec-process (format "npm run %s" script)))

(defun npm-mode-visit-project-file ()
  "Visit the project file."
  (interactive)
  (find-file (npm-mode--project-file)))


;;; Transient definitions
(transient-define-prefix npm-mode--transient-add-dependency ()
  ["Install dependency as"
   ("r" "Regular dependency" npm-mode-npm-install-save-regular)
   ("d" "Dev dependency" npm-mode-npm-install-save-dev)
   ("p" "Peer dependency" npm-mode-npm-install-save-peer)
   ("b" "Bundle dependency" npm-mode-npm-install-save-bundle)
   ("o" "Optional dependency" npm-mode-npm-install-save-optional)])

(transient-define-prefix npm-mode-transient ()
  ["Dependencies"
   ("i" "Install dependencies" npm-mode-npm-install)
   ("s" "Add dependency" npm-mode--transient-add-dependency)
   ("u" "Uninstall depedency" npm-mode-npm-uninstall)
   ("l" "List dependencies" npm-mode-npm-list)]
  ["Actions"
   ("n" "Init project" npm-mode-npm-init)
   ("r" "Run script" npm-mode-npm-run)
   ("v" "Visit package.json" npm-mode-visit-project-file)
   ("q" "Quit" (lambda () (interactive) nil))])


;;; Keymap definition

(defvar npm-mode-command-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map "n" 'npm-mode-npm-init)
    (define-key map "i" 'npm-mode-npm-install)
    (define-key map "s" 'npm-mode-npm-install-save)
    (define-key map "d" 'npm-mode-npm-install-save-dev)
    (define-key map "u" 'npm-mode-npm-uninstall)
    (define-key map "l" 'npm-mode-npm-list)
    (define-key map "r" 'npm-mode-npm-run)
    (define-key map "v" 'npm-mode-visit-project-file)
    (define-key map "t" 'npm-mode-transient)
    map)
  "Keymap for npm-mode commands.")

(defvar npm-mode-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd npm-mode-command-prefix) npm-mode-command-keymap)
    map)
  "Keymap for `npm-mode'.")


;;; Minor mode definitions

;;;###autoload
(define-minor-mode npm-mode
  "Minor mode for working with npm projects."
  :init-value nil
  :lighter npm-mode--modeline-name
  :keymap npm-mode-keymap
  :group 'npm-mode)

;;;###autoload
(define-globalized-minor-mode npm-global-mode
  npm-mode
  npm-mode)

(provide 'npm-mode)
;;; npm-mode.el ends here
