; -*- mode: lisp; package: pacman -*-

;;; pacman.l
;;
;; Copyright (c) 2010 MIYAMUKO Katsuyuki.
;;
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
;; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
;; OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
;; WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

;;; Code:

(in-package :user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require "cmu_loop")

  (unless (find-package :pacman)
    (defpackage :pacman
      (:use :lisp :editor)
      )))

(in-package :pacman)

(export '(pacman-start-from-clipboard
          ))

(defparameter *pacman-debug* nil)
(defparameter *pacman-debug-message-list* nil)
(defparameter *pacman-debug-message-max-count* 10)
(defparameter *pacman-debug-symbols*
  '(*pacman-char-list*
    *pacman-stage*
    *pacman-debug-message-list*
    *pacman-move-history*
    ))

(defparameter *pacman-raw-data* nil)
(defparameter *pacman-timelimit* nil)
(defparameter *pacman-stage-width* nil)
(defparameter *pacman-stage-height* nil)

(defparameter *pacman-stage-dot-char* #\+)
(defparameter *pacman-stage* nil)
(defparameter *pacman-stage-history* nil)

(defparameter *pacman-char-list* nil)
(defparameter *pacman-char-list-history* nil)

(defparameter *pacman-move-history* nil)
(defvar *pacman-game-over-pattern-list* nil)


;;; �\����

(defstruct pacman-char
  id kind x y prev-x prev-y direction state)

(defun pacman-char-enemy-p (char)
  (not (pacman-char-player-p char)))

(defun pacman-char-player-p (char)
  (char= (pacman-char-kind char) #\@))


;;; pacman-mode ������

(defparameter *pacman-regexp-keyword-list* nil)
(setf *pacman-regexp-keyword-list*
      (compile-regexp-keyword-list
       `(
         ("#" nil ((0 . :comment)))
         ("@" nil ((0 . 3)))
         ("[VH]" nil ((0 . 4)))
         ("[LRJ]" nil ((0 . 5)))
         ("\\(time\\|game\\) over!" nil ((0 . (:keyword 1 :bold))))
         )))

(defparameter *pacman-mode-map* nil)
(unless *pacman-mode-map*
  (setf *pacman-mode-map* (make-sparse-keymap))
  ;; common
  (define-key *pacman-mode-map* #\C-h 'pacman-undo-to-intersection)
  (define-key *pacman-mode-map* #\C-z 'pacman-undo-to-intersection)
  (define-key *pacman-mode-map* #\C-M-h 'pacman-undo-to-last-eat)
  (define-key *pacman-mode-map* #\C-M-z 'pacman-undo-to-last-eat)
  (define-key *pacman-mode-map* #\d 'toggle-pacman-debug)
  (define-key *pacman-mode-map* #\e 'pacman-enter)
  (define-key *pacman-mode-map* #\r 'pacman-reset)
  (define-key *pacman-mode-map* #\q 'pacman-quit)
  ;; for Windows user
  (define-key *pacman-mode-map* #\Left 'pacman-move-left)
  (define-key *pacman-mode-map* #\Down 'pacman-move-down)
  (define-key *pacman-mode-map* #\Up 'pacman-move-up)
  (define-key *pacman-mode-map* #\Right 'pacman-move-right)
  (define-key *pacman-mode-map* #\C-m 'pacman-stay)
  ;; for Emacs user
  (define-key *pacman-mode-map* #\C-b 'pacman-move-left)
  (define-key *pacman-mode-map* #\C-n 'pacman-move-down)
  (define-key *pacman-mode-map* #\C-p 'pacman-move-up)
  (define-key *pacman-mode-map* #\C-f 'pacman-move-right)
  (define-key *pacman-mode-map* #\SPC 'pacman-stay)
  ;; for VI user
  (define-key *pacman-mode-map* #\h 'pacman-move-left)
  (define-key *pacman-mode-map* #\j 'pacman-move-down)
  (define-key *pacman-mode-map* #\k 'pacman-move-up)
  (define-key *pacman-mode-map* #\l 'pacman-move-right)
  (define-key *pacman-mode-map* #\. 'pacman-stay)
  )

(defun pacman-mode ()
  (interactive)
  (kill-all-local-variables)
  (setf mode-name "PACK-MAN")
  (setf buffer-mode 'pacman-mode)
  (use-keymap *pacman-mode-map*)
  (make-local-variable 'regexp-keyword-list)
  (setf regexp-keyword-list *pacman-regexp-keyword-list*))


;;; pacman-mode �R�}���h

(defun pacman-start-from-clipboard ()
  (interactive)
  (let ((buf (get-buffer-create "PAC-MAN")))
    (setq need-not-save t)
    (setq auto-save nil)
    (unless (init-frame (get-clipboard-data))
      (delete-buffer buf)
      (return-from pacman-start-from-clipboard))
    (stage-message "start!")
    (pacman-mode)
    (pop-to-buffer buf t)
    ))

(defun pacman-enter (str)
  (interactive "sEnter Answer: ")
  (if (string-matchp "[^hjkl]" str)
      (msgbox "�񓚕�����ɕs���ȕ������܂܂�Ă��܂�: ~S at ~D"
              (match-string 0) (match-beginning 0))
    (progn
      (loop for c across str
        do (progn
             (pacman-move (direction-char>direction c))
             (refresh-screen)
             (do-events)
             (sit-for 0.1)
             )))))

(defun pacman-reset ()
  (interactive)
  (when (init-frame *pacman-raw-data*)
    (stage-message "reset!")))

(defun pacman-quit ()
  (interactive)
  (when (eql buffer-mode 'pacman-mode)
    (delete-buffer (selected-buffer)))
  (init-variables))

(defun pacman-undo-to-intersection ()
  (interactive)
  (while (can-undo-p)
    (restore-frame)
    (multiple-value-bind (_ x y)
        (find-char #\@)
      (when (stage-intersection-p x y)
        (return)))))

(defun pacman-undo-to-last-eat ()
  (interactive)
  (let ((current (count-remaining-dot)))
    (while (and (= current (count-remaining-dot))
                (can-undo-p))
      (restore-frame))))

(defun pacman-move-up ()
  (interactive)
  (pacman-move :up))

(defun pacman-move-down ()
  (interactive)
  (pacman-move :down))

(defun pacman-move-left ()
  (interactive)
  (pacman-move :left))

(defun pacman-move-right ()
  (interactive)
  (pacman-move :right))

(defun pacman-stay ()
  (interactive)
  (pacman-move :stay))

(defun toggle-pacman-debug ()
  (interactive)
  (setf *pacman-debug* (not *pacman-debug*))
  (render-stage))

(defun d (fmt &rest args)
  (push (apply 'format nil fmt args) *pacman-debug-message-list*)
  (let ((n (- (length *pacman-debug-message-list*)
              *pacman-debug-message-max-count*)))
    (when (< 0 n)
      (setf *pacman-debug-message-list*
            (nbutlast *pacman-debug-message-list* n)))))


;;; ��ԊǗ�

(defun init-variables ()
  (setf *pacman-debug-message-list* nil
        *pacman-raw-data* nil
        *pacman-timelimit* nil
        *pacman-stage-width* nil
        *pacman-stage-height* nil
        *pacman-stage* nil
        *pacman-stage-history* nil
        *pacman-char-list* nil
        *pacman-char-list-history* nil
        *pacman-move-history* nil))


(defun pop-move-history ()
  (setf *pacman-move-history* (nbutlast *pacman-move-history*)))

(defun save-move-history (direction)
  (let ((char (direction->direction-char direction)))
    ;; �\�����������������邽�ߕۑ����ɏ��Ԃ��ێ����� (push ���g��Ȃ�)
    (setf *pacman-move-history* (append *pacman-move-history* (list char)))))

(defun init-frame (stage)
  (init-variables)
  (init-stage stage))

(defun new-frame ()
  (push (copy-stage *pacman-stage*) *pacman-stage-history*)
  (push (copy-char-list *pacman-char-list*) *pacman-char-list-history*)
  )

(defun can-undo-p ()
  (not (null *pacman-move-history*)))

(defun restore-frame ()
  (if (can-undo-p)
      (progn
        (setf *pacman-stage* (pop *pacman-stage-history*)
              *pacman-char-list* (pop *pacman-char-list-history*))
        (pop-move-history)
        (render-stage))
    (progn
      (stage-message "����ȏ�undo�ł��܂���"))))

(defun init-stage (stage-str)
  (handler-case
      (progn
        (let ((stage (split-string stage-str #\LFD)))
          (setf *pacman-timelimit* (parse-integer (pop stage)))
          (when (string-matchp "^\\([0-9]+\\) +\\([0-9]+\\)$" (pop stage))
            (setf *pacman-stage-width* (parse-integer (match-string 1)))
            (setf *pacman-stage-height* (parse-integer (match-string 2))))

          ;; �v���C���[�ƓG�̃��X�g���쐬
          (setf *pacman-char-list* (make-pacman-char-list stage))
          (setf *pacman-stage* (make-stage stage))
          (setf *pacman-raw-data* stage-str)))
    (error (c)
      (msgbox "���͂��s���ł��B�N���b�v�{�[�h�� DevQuiz �̓��͂��R�s�[���Ď��s���Ă�������")
      nil
      )))

(defun make-stage (stage)
  (mapcar #'(lambda (line)
              (substitute-string
               (substitute-string line "[A-Z@]" " ")
               "\\." (string *pacman-stage-dot-char*)))
          stage))

;; ������Ԃ͎��̏����𖞂����܂��B
;;
;; - ����̓G(���Ȃ��p���ŕ\�����G)���������݂��邱�Ƃ�����܂��B
(defun make-pacman-char-list (stage)
  (let ((r (loop with id = 0 for line in stage and y = 0 then (1+ y) append
             (loop for cell across line and x = 0 then (1+ x)
               when (or (alpha-char-p cell)
                        (char= cell #\@))
               collect (make-pacman-char
                        ;; player �� id �� 0
                        :id (if (char= cell #\@) 0 (incf id))
                        :kind cell :x x :y y)))))
    ;; player ���擪�ɗ���悤�ɂ���
    (stable-sort r #'< :key #'pacman-char-id)))

(defun pacman-player-char ()
  (car *pacman-char-list*))

(defun pacman-enemy-char-list ()
  (cdr *pacman-char-list*))

;; ���@�ƓG���Փ˂���ƃQ�[���I�[�o�[�ł��B
;; �����Ŏ��@�Ƃ���G x ������ t = 1, 2, ..., T �ɏՓ˂���Ƃ͎��̂����ꂩ�̏����𖞂����ꍇ�������܂��B
;;
;; - ���� t �Ɏ��@�ƓG x �������}�X�ɑ��݂���B
;; - ���� t-1 �ɂ����鎩�@�ƓG x �̈ʒu�ƁA���� t �ɂ����鎩�@�ƓG x �̈ʒu����������Ă���B
;;
;; ���� t �ɏՓ˂����ꍇ�A���@�͎��� t �Ƀh�b�g��������邱�Ƃ͂ł��܂���B
(defun game-clear-p ()
  (zerop (count-remaining-dot)))

(defun game-over-p ()
  (let ((player (pacman-player-char))
        (enemy-list (pacman-enemy-char-list)))
    (or (game-clear-p)
        (time-over-p)
        (find-if #'(lambda (enemy)
                     (and (= (pacman-char-x player) (pacman-char-x enemy))
                          (= (pacman-char-y player) (pacman-char-y enemy))
                          ))
                 enemy-list)
        (find-if #'(lambda (enemy)
                     (and (not (first-frame-p))
                          (= (pacman-char-x player) (pacman-char-prev-x enemy))
                          (= (pacman-char-y player) (pacman-char-prev-y enemy))
                          (= (pacman-char-prev-x player) (pacman-char-x enemy))
                          (= (pacman-char-prev-y player) (pacman-char-y enemy))
                          ))
                 enemy-list))))

(defun first-frame-p ()
  ;; �ŏ��̃t���[�� (t = 0 �̏ꍇ) �Ȃ� t
  (= (current-time-elapsed) 0))

(defun time-over-p ()
  (<= (current-time-remaining) 0))

(defun current-time-elapsed ()
  (length *pacman-move-history*))

(defun current-time-remaining ()
  (- *pacman-timelimit* (current-time-elapsed)))


;;; �ړ��Ǘ�

;; �Q�[���̐i�s
;; ���� t = 0, 1, ..., T-1 �ɂ����āA���@�ƓG�ׂ͗荇�� 4 �����̃}�X�Ɉړ����邱�Ƃ��ł��܂��B
;; �G�͕K���ړ����܂����A���@�͂��̏�ɗ��܂邱�Ƃ�I�����邱�Ƃ��ł��܂��B
;; �S�@�̍s���͓����ɍs���A������ 1 �i�߂��܂��B

;; ���@���h�b�g�̂���}�X�ɐi������ƁA�h�b�g�� 1 ������邱�Ƃ��ł��܂��B
;; ��x�h�b�g����������}�X����͓�x�ƃh�b�g�𓾂邱�Ƃ͂ł��܂���B
;; �G���h�b�g�̂���}�X�ɐi�����Ă������N����܂���B

(defun pacman-move (direction)
  (when (game-over-p)
    (return-from pacman-move nil))
  (unless (can-move-p #\@ direction)
    (stage-message "�ǂł�")
    (return-from pacman-move nil))
  (new-frame)
  (move-enemy)
  (move-player direction)
  (when (time-over-p)
    (stage-message "time over!")
    (return-from pacman-move nil))
  (when (game-over-p)
    (pushnew (pacman-answer) *pacman-game-over-pattern-list* :test #'string=)
    (stage-message "game over!")
    (return-from pacman-move nil))
  ;; ���� t �ɏՓ˂����ꍇ�A���@�͎��� t �Ƀh�b�g��������邱�Ƃ͂ł��܂���B
  (eat-dot)
  (when (game-clear-p)
    (stage-message "all your dot are belong to pacman!")
    (ed::kill-new (pacman-answer))
    (setf *kill-ring-newer-than-clipboard-p* t
          *clipboard-newer-than-kill-ring-p* nil)
    (message "kill-ring�ɉ񓚂��R�s�[���܂���")
    (return-from pacman-move nil))
  (render-stage))

(defun move-player (direction)
  (multiple-value-bind (x y)
      (move-char #\@ direction)
    (save-move-history direction)))

(defun move-char (char-designator direction)
  (multiple-value-bind (char next-x next-y x y)
      (char-next-pos char-designator direction)
    (when (not (wall-p next-x next-y))
      (setf (pacman-char-x char) next-x
            (pacman-char-y char) next-y
            (pacman-char-prev-x char) x
            (pacman-char-prev-y char) y
            (pacman-char-direction char) direction
            )
      (values next-x next-y))
    ))

;; ���� t = 0 �ɂ����ẮA�����ʒu�� ���A���A��A�E �̏��ōŏ��ɐi���\�ȃ}�X�̕����Ɉړ����܂��B
;; ���� t = 1, 2, ..., T-1 �ɂ�����ړ������́A���݈ʒu�̎�ʂɂ���Ď��̂悤�Ɍ��肳��܂��B
;; - �s���~�܂�}�X�̏ꍇ
;;   - �B��i���\�ȗאڃ}�X�Ɉړ����܂��B
;; - �ʘH�}�X�̏ꍇ
;;   - ���� t-1 �ɋ����}�X�ȊO�̐i���\�ȗאڂ���}�X�Ɉړ����܂��B
(defun move-enemy ()
  (dolist (enemy (pacman-enemy-char-list))
    (let ((x (pacman-char-x enemy))
          (y (pacman-char-y enemy)))
      (cond ((first-frame-p)              ; t = 0 �̏ꍇ
             (d "t = 0 ~S" enemy)
             (move-first-space enemy (list :down :left :up :right)))
            ((stage-1-way-cell-p x y)     ; �s���~�܂�}�X�̏ꍇ
             (d "1-way ~S" enemy)
             (move-first-space enemy (list :down :left :up :right)))
            ((stage-2-way-cell-p x y)         ; �ʘH�}�X�̏ꍇ
             (d "2-way ~S" enemy)
             (move-if #'(lambda (direction)
                          (multiple-value-bind (char next-x next-y x y)
                              (char-next-pos enemy direction)
                            (or (/= (pacman-char-prev-x enemy) next-x)
                                (/= (pacman-char-prev-y enemy) next-y))))
                      enemy (list :up :right :down :left)))
            ((stage-intersection-p x y)       ; �����_�}�X�̏ꍇ
             (d "x-way ~S" enemy)
             (move-enemy-on-intersection enemy))
            (t
             (error "Unknown cell")) ; bug
            ))))

(defparameter *enemy-move-function-on-intersection-alist*
  '((#\V . move-enemy-on-intersection-V)
    (#\H . move-enemy-on-intersection-H)
    (#\L . move-enemy-on-intersection-L)
    (#\R . move-enemy-on-intersection-R)
    (#\J . move-enemy-on-intersection-J)
    ))
(defun move-enemy-on-intersection (enemy)
  (let* ((id (pacman-char-id enemy))
         (kind (pacman-char-kind enemy))
         (fn (cdr (assoc kind *enemy-move-function-on-intersection-alist* :test #'char=))))
    (funcall fn enemy)))

;; - �����_�}�X�̏ꍇ
;;   - �G V
;;     - �G���猩�����@�̑��Έʒu�� (dx, dy) �ƕ\�����̂Ƃ��܂��B
;;     - ���̃��[�����ォ�珇�ɓK�p���A�ŏ��ɑI�΂ꂽ�����Ɉړ����܂��B
;;       - dy �� 0 �ł��� dy �̕��������ɂ���}�X���i���\�ł���΁A���̕����Ɉړ����܂��B
;;       - dx �� 0 �ł��� dx �̕��������ɂ���}�X���i���\�ł���΁A���̕����Ɉړ����܂��B
;;       - ���݈ʒu�� ���A���A��A�E �̏��ōŏ��ɐi���\�ȃ}�X�̕����Ɉړ�����B
(defun move-enemy-on-intersection-V (enemy)
  (move-enemy-on-intersection-VH enemy t))

;;   - �G H
;;     - �G V �Ƃقړ����ł��B�B��قȂ�̂� �A�i�s���������߂郋�[���̂����A
;;       �ŏ��̓�̃��[���̓K�p����������ւ��Ƃ���ł��B
;;       ���Ȃ킿�A��� dx �� 0 �̃`�F�b�N���s�Ȃ��A���� dy �� 0 �̃`�F�b�N���s���܂��B
(defun move-enemy-on-intersection-H (enemy)
  (move-enemy-on-intersection-VH enemy nil))

(defun move-enemy-on-intersection-VH (enemy v)
  (multiple-value-bind (dx dy)
      (relative-position (find-char #\@) enemy)
    (labels ((move1 ()
               (let ((direction (if (minusp dy) :up :down)))
                 (when (and (not (zerop dy))
                            (can-move-p enemy direction))
                   (move-char enemy direction))))
             (move2 ()
               (let ((direction (if (minusp dx) :left :right)))
                 (when (and (not (zerop dx))
                            (can-move-p enemy direction))
                   (move-char enemy direction))))
             (move3 ()
               (move-first-space enemy (list :down :left :up :right))))
      (if v
          (or (move1) (move2) (move3))
        (or (move2) (move1) (move3))))))

;;   - �G L
;;     - ���݈ʒu�ւ̐i���������猩�đ��ΓI�� ���A�O�A�E �̏��ōŏ��ɐi���\�ȃ}�X�̕����Ɉړ����܂��B
(defun move-enemy-on-intersection-L (enemy)
  (move-first-space-relative enemy (list :left :up :right)))

;;   - �G R
;;     - ���݈ʒu�ւ̐i���������猩�đ��ΓI�� �E�A�O�A�� �̏��ōŏ��ɐi���\�ȃ}�X�̕����Ɉړ����܂��B
(defun move-enemy-on-intersection-R (enemy)
  (move-first-space-relative enemy (list :right :up :left)))

;;   - �G J
;;     - �����_�}�X�ɓ��邽�тɁA�ŏ��͓GL�̍s���A����͓GR�̍s���A����Ɏ���͂܂��GL�̍s���A�ƌJ��Ԃ��܂��B
(defun move-enemy-on-intersection-J (enemy)
  (if (not (pacman-char-state enemy))
      (move-enemy-on-intersection-L enemy)
    (move-enemy-on-intersection-R enemy))
  (setf (pacman-char-state enemy) (not (pacman-char-state enemy))))


(defun move-if (fn enemy absolute-directions)
  (move-char enemy (find-if fn (find-moveable-directions enemy absolute-directions))))

(defun move-first-space (enemy absolute-directions)
  (move-char enemy (car (find-moveable-directions enemy absolute-directions))))

(defun find-moveable-directions (char absolute-directions)
  (remove-if-not #'(lambda (direction)
                     (can-move-p char direction))
                 absolute-directions))

(defun move-first-space-relative (enemy relative-directions)
  (let ((absolute-directions
         (mapcar #'(lambda (rel-dir)
                     (direction-relative->absolute rel-dir (pacman-char-direction enemy)))
                 relative-directions)))
    (d "~S" (list (pacman-char-kind enemy) relative-directions absolute-directions))
    (move-char enemy (car (find-moveable-directions enemy absolute-directions)))))

(defun direction-relative->absolute (relative-direction current-direction)
  (let* ((directions (list :up :right :down :left))
         (n (position current-direction directions))
         (pos (position relative-direction directions)))
    (nth pos (rotate-list-left directions n))))

(defun rotate-list-left (list n)
   (if (zerop n)
       list
     (rotate-list-left (append (rest list) (list (first list))) (- n 1))))



;;; �X�e�[�W�Ǘ�

;; �t�B�[���h���̐i���\�}�X�́A���� 4 �����ɗׂ荇���}�X�̂����i���\�Ȃ��̂̐��ɉ����āA
;; �s���~�܂�}�X�A�ʘH�}�X�A�����_�}�X�� 3 ��ނɕ��ނ���܂��B
;; 1 ��������ꍇ���s���~�܂�}�X�A2 ��������ꍇ���ʘH�}�X�A3,4 ��������ꍇ�������_�}�X�ƂȂ�܂��B

(defun stage-1-way-cell-p (x y)
  (= (stage-count-way x y) 1))

(defun stage-2-way-cell-p (x y)
  (= (stage-count-way x y) 2))

(defun stage-3-way-cell-p (x y)
  (= (stage-count-way x y) 3))

(defun stage-4-way-cell-p (x y)
  (= (stage-count-way x y) 4))

(defun stage-intersection-p (x y)
  (or (stage-3-way-cell-p x y)
      (stage-4-way-cell-p x y)))

(defun stage-count-way (x y)
  (count-if-not #'(lambda (xy)
                    (wall-p (car xy) (cdr xy)))
                (list (cons (+ x 0) (+ y 1)) ; up
                      (cons (+ x 1) (+ y 0)) ; right
                      (cons (- x 1) (+ y 0)) ; left
                      (cons (+ x 0) (- y 1)) ; down
                      )))

;; . �͂��̃}�X�Ƀh�b�g���u����Ă��邱�Ƃ�\���܂��B
;; �h�b�g�łȂ��i���\�ȃ}�X�A���Ȃ킿���@�ƓG�̏����ʒu����ы󂫃}�X�ɂ̓h�b�g�͒u����܂���B
(defun count-remaining-dot ()
  (loop for line in *pacman-stage*
    summing (count *pacman-stage-dot-char* line)))

(defun eat-dot ()
  (multiple-value-bind (_ x y)
      (find-char #\@)
    (set-stage-at x y #\SPC)))

;; # �͕ǂ�\���܂��B���̃}�X�ɂ͎��@���G���i�����邱�Ƃ��ł��܂���B
;; �t�ɕǈȊO�̃}�X�ɂ͂��ׂĐi���\�ł��B
(defun can-move-p (char-designator direction)
  (multiple-value-bind (char next-x next-y x y)
      (char-next-pos char-designator direction)
    (not (wall-p next-x next-y))))

(defun wall-p (x y)
  (char= (stage-at x y) #\#))


;;; �X�e�[�W�̕`��

(defparameter *stage-message* nil)
(defun stage-message (fmt &rest args)
  (setf *stage-message* (apply 'format nil fmt args))
  (render-stage)
  (setf *stage-message* nil))

;; ���@�̓�������\����������o�͂��Ă��������B
;; ������� t = 0, 1, ..., T-1 �ɂ����鎩�@�̍s����\��������A���������̂ł��B
;;
;; h	�������ֈړ�
;; j	�������ֈړ�
;; k	������ֈړ�
;; l	�E�����ֈړ�
;; .	���̏�ɗ��܂�

(defun render-stage ()
  (erase-buffer (selected-buffer))
  (let ((answer (pacman-answer)))
    (puts "~{~A~%~}" (stage-view))
    (puts "")
    (puts "remaining time: ~A, remaining dot ~A" (current-time-remaining) (count-remaining-dot))
    (puts "message: ~A" (or *stage-message* ""))
    (puts "answer: ~A" answer)
    (save-excursion
      (puts "")
      (puts "game over pattern:")
      (dolist (bad *pacman-game-over-pattern-list*)
        (when (and (<= (length answer) (length bad))
                   (string= answer bad :end2 (length answer)))
          (puts "  ~A~%" bad)))
      (when *pacman-debug*
        (dolist (sym *pacman-debug-symbols*)
          (let ((v (ignore-errors (symbol-value sym))))
            (puts "")
            (puts "~S:" sym)
            (cond ((null v)
                   (puts "  nil"))
                  ((listp v)
                   (puts "~{  ~S~%~}" v))
                  (t
                   (puts "  ~S" v)))))
        (puts "")))))

(defun pacman-answer ()
  (format nil "~{~A~}" *pacman-move-history*))

(defun stage-view ()
  (flet ((render-char (stage char)
           (set-stage-at (pacman-char-x char)
                         (pacman-char-y char)
                         (pacman-char-kind char)
                         stage)))
    (let ((view (copy-stage *pacman-stage*)))
      (dolist (char (pacman-enemy-char-list))
        (render-char view char))
      (render-char view (pacman-player-char))
      view)))

(defun puts (fmt &rest args)
  (let ((msg (apply 'format nil fmt args)))
    (insert msg)
    (when (or (string= msg "")
              (not (char= (char msg (- (length msg) 1)) #\LFD)))
      (insert #\LFD))))

(defparameter *direction-definition*
  '((:left  #\h -1  0)
    (:down  #\j  0  1)
    (:up    #\k  0 -1)
    (:right #\l  1  0)
    (:stay  #\.  0  0)
    ))

(defun direction-char>direction (direction-char)
  (let ((def (find direction-char *direction-definition* :key #'cadr)))
    (car def)))

(defun direction->direction-char (direction)
  (let ((def (find direction *direction-definition* :key #'car)))
    (cadr def)))

(defun direction->diff (direction)
  (let ((def (find direction *direction-definition* :key #'car)))
    (values-list (cddr def))))

(defun char-next-pos (char-designator direction)
  (multiple-value-bind (dx dy)
      (direction->diff direction)
    (multiple-value-bind (char x y)
        (find-char char-designator)
      (values char (+ x dx) (+ y dy) x y))))

(defun find-char (char-designator)
  (let ((char (if (pacman-char-p char-designator)
                  char-designator
                (find-if #'(lambda (char)
                             (or (eql (pacman-char-id char) char-designator)
                                 (eql (pacman-char-kind char) char-designator)))
                         *pacman-char-list*))))
    (unless char
      (error "Char not found: ~S" char-designator))
    (values char (pacman-char-x char) (pacman-char-y char))))

;; �e�Z���̈ʒu�͍���� (1, 1), �E���� (W, H) �Ƃ�����W�ŕ\����܂��B
(defun relative-position (char1 char2)
  (values (- (pacman-char-x char1) (pacman-char-x char2))
          (- (pacman-char-y char1) (pacman-char-y char2))))

(defun stage-at (x y &optional (stage *pacman-stage*))
  (elt (nth y stage) x))

(defun set-stage-at (x y value &optional (stage *pacman-stage*))
  (let ((lst (nth y stage)))
    (setf (elt lst x) value)))


;;; utility

(defun copy-stage (stage)
  (mapcar #'copy-seq stage))

(defun copy-char-list (char-list)
  (mapcar #'copy-pacman-char char-list))


(provide "pacman")

;;; End