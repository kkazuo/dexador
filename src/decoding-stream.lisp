(in-package :cl-user)
(defpackage dexador.decoding-stream
  (:use :cl)
  (:import-from :trivial-gray-streams
                :fundamental-character-input-stream
                :stream-read-char)
  (:import-from :babel
                :*string-vector-mappings*
                :unicode-char)
  (:import-from :babel-encodings
                :*default-character-encoding*
                :get-character-encoding
                :code-point-counter
                :enc-max-units-per-char
                :lookup-mapping)
  (:export :make-decoding-stream
           :decoding-stream)
  (:documentation "Provides character decoding stream.
Similar to flexi-input-stream, except this uses Babel for decoding."))
(in-package :dexador.decoding-stream)

(declaim (type fixnum +buffer-size+))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defconstant +buffer-size+ 128))

(defclass decoding-stream (fundamental-character-input-stream)
  ((stream :type stream
           :initarg :stream
           :initform (error ":stream is required")
           :accessor decoding-stream-stream)
   (encoding :initarg :encoding
             :initform (error ":encoding is required")
             :accessor decoding-stream-encoding)
   (buffer :type (simple-array (unsigned-byte 8) (#.+buffer-size+))
           :initform (make-array +buffer-size+ :element-type '(unsigned-byte 8))
           :accessor decoding-stream-buffer)
   (buffer-position :type fixnum
                    :initform +buffer-size+
                    :accessor decoding-stream-buffer-position)
   (buffer-end-position :type fixnum
                        :initform -1
                        :accessor decoding-stream-buffer-end-position)))

(defmethod initialize-instance :after ((stream decoding-stream) &rest initargs)
  (declare (ignore initargs))
  (with-slots (encoding) stream
    (when (keywordp encoding)
      (setf encoding (get-character-encoding encoding)))))

(defun make-decoding-stream (stream &key (encoding babel-encodings:*default-character-encoding*))
  (let ((decoding-stream (make-instance 'decoding-stream
                                        :stream stream
                                        :encoding encoding)))
    (fill-buffer decoding-stream)
    decoding-stream))

(defun fill-buffer (stream)
  (declare (optimize speed))
  (with-slots (stream buffer buffer-position buffer-end-position) stream
    (declare (type (simple-array (unsigned-byte 8) (#.+buffer-size+)) buffer)
             (type fixnum buffer-position))
    (let ((to-read (- +buffer-size+ buffer-position)))
      (declare (type fixnum to-read))
      (replace buffer buffer
               :start1 0
               :start2 buffer-position
               :end2 +buffer-size+)
      (setf buffer-position 0)
      (let ((n (read-sequence buffer stream :start to-read)))
        (declare (type fixnum n))
        (unless (= n +buffer-size+)
          (setf buffer-end-position n))))))

(defun needs-to-fill-buffer-p (stream)
  (declare (optimize speed))
  (when (/= -1 (the fixnum (decoding-stream-buffer-end-position stream)))
    (return-from needs-to-fill-buffer-p nil))

  (with-slots (buffer-position encoding) stream
    (< (- +buffer-size+ (the fixnum buffer-position))
       (the fixnum (enc-max-units-per-char encoding)))))

(defmethod stream-read-char ((stream decoding-stream))
  (declare (optimize speed))
  (when (needs-to-fill-buffer-p stream)
    (fill-buffer stream))

  (when (= (the fixnum (decoding-stream-buffer-end-position stream))
           (the fixnum (decoding-stream-buffer-position stream)))
    (return-from stream-read-char :eof))

  (with-slots (buffer buffer-position encoding) stream
    (let* ((mapping (lookup-mapping *string-vector-mappings* encoding))
           (counter (code-point-counter mapping)))
      (declare (type function counter))
      (multiple-value-bind (size new-end)
          (funcall counter buffer buffer-position +buffer-size+ 1)
        (declare (ignore size))
        (let ((string (make-string 1 :element-type 'babel:unicode-char)))
          (funcall (the function (babel-encodings:decoder mapping))
                   buffer buffer-position new-end string 0)
          (setf buffer-position new-end)
          (aref string 0))))))

(defmethod open-stream-p ((stream decoding-stream))
  (open-stream-p (decoding-stream-stream stream)))

(defmethod stream-element-type ((stream decoding-stream))
  'unicode-char)

(defmethod close ((stream decoding-stream) &key abort)
  (with-slots (stream) stream
    (when (open-stream-p stream)
      (close stream :abort abort))))