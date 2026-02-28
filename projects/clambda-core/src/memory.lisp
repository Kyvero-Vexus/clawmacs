;;;; src/memory.lisp — Workspace memory system for clawmacs-core

(in-package #:clawmacs/memory)

(defparameter *embedding-model* "text-embedding-nomic-embed-text-v1.5"
  "Default embedding model for memory vector search.")

(defparameter *embedding-base-url* "http://192.168.1.189:1234/v1"
  "Base URL for the embedding API endpoint.")

(defstruct (memory-entry (:constructor %make-memory-entry))
  (name    "" :type string)
  (path    "" :type string)
  (content "" :type string))

(defstruct (workspace-memory (:constructor %make-workspace-memory))
  (path    "" :type string)
  (entries nil :type list))

(defparameter *priority-files*
  '("SOUL.md" "AGENTS.md" "IDENTITY.md" "TEAM.md" "ROADMAP.md"
    "MEMORY.md" "README.md")
  "Filenames loaded first (if present) to ensure key context appears early.")

(defun %config-option (name fallback)
  (or (ignore-errors
        (let* ((pkg (find-package '#:clawmacs/config))
               (sym (and pkg (find-symbol name pkg))))
          (and sym (boundp sym) (symbol-value sym))))
      fallback))

(defun %embedding-model ()
  (%config-option "*EMBEDDING-MODEL*" *embedding-model*))

(defun %embedding-base-url ()
  (%config-option "*EMBEDDING-BASE-URL*" *embedding-base-url*))

(defun read-md-file (path)
  (handler-case
      (uiop:read-file-string path)
    (error () nil)))

(defun md-file-p (pathname)
  (let ((type (pathname-type pathname)))
    (and type (string-equal type "md"))))

(defun find-md-files (dir-path)
  (let* ((truepath  (uiop:ensure-directory-pathname
                     (if (stringp dir-path)
                         (uiop:parse-native-namestring dir-path)
                         dir-path)))
         (all-files (uiop:directory-files truepath)))
    (remove-if-not #'md-file-p all-files)))

(defun load-entry (pathname)
  (let ((content (read-md-file pathname)))
    (when content
      (%make-memory-entry
       :name    (file-namestring pathname)
       :path    (namestring pathname)
       :content content))))

(defun sort-by-priority (pathnames)
  (let ((priority-set (make-hash-table :test #'equal)))
    (loop :for name :in *priority-files*
          :for i :from 0
          :do (setf (gethash name priority-set) i))
    (sort (copy-list pathnames)
          (lambda (a b)
            (let ((ai (gethash (file-namestring a) priority-set))
                  (bi (gethash (file-namestring b) priority-set)))
              (cond
                ((and ai bi) (< ai bi))
                (ai t)
                (bi nil)
                (t  (string< (file-namestring a)
                             (file-namestring b)))))))))

(defun load-workspace-memory (workspace-path
                               &key (max-entry-chars 50000)
                                    (max-total-chars  200000)
                                    subdirs)
  (let* ((base-dir  (uiop:ensure-directory-pathname
                     (if (stringp workspace-path)
                         (uiop:parse-native-namestring workspace-path)
                         workspace-path)))
         (all-mds   (find-md-files (namestring base-dir)))
         (sub-mds   (when subdirs
                      (loop :for sd :in subdirs
                            :append (find-md-files
                                     (namestring
                                      (uiop:ensure-directory-pathname
                                       (merge-pathnames sd base-dir)))))))
         (all-paths (append all-mds sub-mds))
         (sorted    (sort-by-priority all-paths))
         (entries   nil)
         (total     0))

    (dolist (p sorted)
      (when (>= total max-total-chars)
        (return))
      (let ((entry (load-entry p)))
        (when entry
          (when (> (length (memory-entry-content entry)) max-entry-chars)
            (setf (memory-entry-content entry)
                  (concatenate 'string
                               (subseq (memory-entry-content entry) 0 max-entry-chars)
                               (format nil "~%...[truncated]"))))
          (incf total (length (memory-entry-content entry)))
          (push entry entries))))

    (%make-workspace-memory
     :path    (namestring base-dir)
     :entries (nreverse entries))))

(defun search-memory (workspace-memory query)
  (let ((q (string-downcase query))
        (results nil))
    (dolist (entry (workspace-memory-entries workspace-memory))
      (let* ((lower  (string-downcase (memory-entry-content entry)))
             (pos    (search q lower)))
        (when pos
          (let* ((start  (max 0 (- pos 100)))
                 (end    (min (length (memory-entry-content entry))
                              (+ pos (length query) 100)))
                 (excerpt (subseq (memory-entry-content entry) start end)))
            (push (cons entry excerpt) results)))))
    (nreverse results)))

(defun memory-context-string (workspace-memory &key (separator "---"))
  (if (null (workspace-memory-entries workspace-memory))
      ""
      (with-output-to-string (s)
        (format s "# Workspace Memory~%~%")
        (dolist (entry (workspace-memory-entries workspace-memory))
          (format s "## ~a~%~%" (memory-entry-name entry))
          (write-string (memory-entry-content entry) s)
          (format s "~%~%~a~%~%" separator)))))

(defun %default-memory-workspace ()
  (or (ignore-errors
        (let* ((pkg (find-package '#:clawmacs/config))
               (sym (and pkg (find-symbol "*CLAWMACS-HOME*" pkg))))
          (and sym (symbol-value sym))))
      (uiop:ensure-directory-pathname
       (merge-pathnames ".clawmacs/" (user-homedir-pathname)))))

(defun %query-keywords (query)
  (remove-if (lambda (s) (< (length s) 2))
             (cl-ppcre:split "[^[:alnum:]_]+" (string-downcase query))))

(defun %keyword-memory-search (query &key (max-results 5))
  (let* ((mem (load-workspace-memory (%default-memory-workspace)
                                     :subdirs '("memory")))
         (keywords (%query-keywords query))
         (results nil))
    (dolist (entry (workspace-memory-entries mem))
      (let* ((content (memory-entry-content entry))
             (lower (string-downcase content))
             (score 0)
             (pos nil))
        (when (search (string-downcase query) lower)
          (incf score 4)
          (setf pos (search (string-downcase query) lower)))
        (dolist (kw keywords)
          (let ((p (search kw lower)))
            (when p
              (incf score)
              (unless pos (setf pos p)))))
        (when (> score 0)
          (let* ((start (max 0 (- (or pos 0) 100)))
                 (end (min (length content) (+ (or pos 0) 200))))
            (push (list :file (memory-entry-name entry)
                        :path (memory-entry-path entry)
                        :score score
                        :excerpt (subseq content start end))
                  results)))))
    (let ((sorted (sort results #'> :key (lambda (r) (getf r :score)))))
      (subseq sorted 0 (min max-results (length sorted))))))

(defun %chunk-text (text)
  (remove-if (lambda (s) (< (length s) 20))
             (mapcar (lambda (s) (string-trim '(#\Space #\Tab #\Newline #\Return) s))
                     (cl-ppcre:split "\n\s*\n+" text))))

(defun %memory-chunks (workspace-memory)
  (loop :for entry :in (workspace-memory-entries workspace-memory)
        :append (loop :for chunk :in (%chunk-text (memory-entry-content entry))
                      :collect (list :file (memory-entry-name entry)
                                     :path (memory-entry-path entry)
                                     :text chunk))))

(defun %embeddings-cache-path ()
  (merge-pathnames "embeddings-cache.json" (%default-memory-workspace)))

(defun %load-embedding-cache ()
  (let ((cache (make-hash-table :test #'equal))
        (path (%embeddings-cache-path)))
    (when (probe-file path)
      (handler-case
          (let ((raw (com.inuoe.jzon:parse (uiop:read-file-string path))))
            (let ((items (gethash "items" raw)))
              (when items
                (map nil
                     (lambda (item)
                       (let ((k (gethash "key" item))
                             (v (gethash "embedding" item)))
                         (when (and k v)
                           (setf (gethash k cache) (coerce v 'vector)))))
                     items))))
        (error () nil)))
    cache))

(defun %save-embedding-cache (cache)
  (let* ((path (%embeddings-cache-path))
         (items (loop :for k :being :the :hash-keys :of cache
                      :using (hash-value v)
                      :collect (let ((row (make-hash-table :test #'equal)))
                                 (setf (gethash "key" row) k)
                                 (setf (gethash "embedding" row) (coerce v 'vector))
                                 row)))
         (obj (make-hash-table :test #'equal)))
    (setf (gethash "items" obj) (coerce items 'vector))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (write-string (com.inuoe.jzon:stringify obj) out))))

(defun embed-text (text &key (model (%embedding-model)) (base-url (%embedding-base-url)))
  (handler-case
      (let* ((url (format nil "~a/embeddings" (string-right-trim "/" base-url)))
             (req (make-hash-table :test #'equal)))
        (setf (gethash "model" req) model)
        (setf (gethash "input" req) text)
        (multiple-value-bind (body status)
            (dexador:post url
                          :headers '(("Content-Type" . "application/json"))
                          :content (com.inuoe.jzon:stringify req)
                          :force-string t)
          (declare (ignore status))
          (let* ((obj (com.inuoe.jzon:parse body))
                 (data (gethash "data" obj))
                 (first-row (and data (> (length data) 0) (aref data 0)))
                 (embedding (and first-row (gethash "embedding" first-row))))
            (and embedding (coerce embedding 'vector)))))
    (error () nil)))

(defun cosine-similarity (a b)
  (let ((len (min (length a) (length b))))
    (if (zerop len)
        0.0d0
        (loop :with dot = 0.0d0
              :with ma = 0.0d0
              :with mb = 0.0d0
              :for i :from 0 :below len
              :for av = (coerce (aref a i) 'double-float)
              :for bv = (coerce (aref b i) 'double-float)
              :do (incf dot (* av bv))
                  (incf ma (* av av))
                  (incf mb (* bv bv))
              :finally (return (if (or (zerop ma) (zerop mb))
                                   0.0d0
                                   (/ dot (* (sqrt ma) (sqrt mb)))))))))

(defun memory-search (query &key (max-results 5))
  (let* ((mem (load-workspace-memory (%default-memory-workspace)
                                     :subdirs '("memory")))
         (chunks (%memory-chunks mem))
         (cache (%load-embedding-cache))
         (query-emb (embed-text query)))
    (unless query-emb
      (return-from memory-search (%keyword-memory-search query :max-results max-results)))
    (let ((results nil)
          (cache-updated nil))
      (dolist (chunk chunks)
        (let* ((text (getf chunk :text))
               (key (format nil "~a::~a" (%embedding-model) text))
               (emb (or (gethash key cache)
                        (let ((fresh (embed-text text)))
                          (when fresh
                            (setf (gethash key cache) fresh)
                            (setf cache-updated t))
                          fresh))))
          (when emb
            (push (list :file (getf chunk :file)
                        :path (getf chunk :path)
                        :score (cosine-similarity query-emb emb)
                        :excerpt text)
                  results))))
      (when cache-updated
        (%save-embedding-cache cache))
      (if results
          (let ((sorted (sort results #'> :key (lambda (r) (getf r :score)))))
            (subseq sorted 0 (min max-results (length sorted))))
          (%keyword-memory-search query :max-results max-results)))))