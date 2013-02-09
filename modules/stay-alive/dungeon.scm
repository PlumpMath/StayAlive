;; Updated!
(define-module (stay-alive dungeon)
  #:use-module (shelf shelf)
  #:use-module (shelf shelf-util)
  #:use-module (stay-alive extensions)
  #:use-module (stay-alive shared)
  #:use-module (srfi srfi-1)
  #:use-module (stay-alive util)
  #:use-module (system vm objcode)
  #:use-module (system vm program)
  #:use-module (ice-9 threads)
  #:use-module (system base compile)
  #:use-module (stay-alive level)
  #:use-module (stay-alive square)
  #:use-module (stay-alive player)
  #:use-module (stay-alive agent)
  #:export (Dungeon StandardDungeon))

(define make-standard-level 
  (method (depth)
    (or (vector-ref ($ this 'level-cache) depth)
	(let* ((level 
		(instance Level 
			  #:args (list this depth (= depth 0) (= depth ($ this 'depth)))))
	       (dimensions (array-dimensions ($ level 'squares)))
	       (tile-info (make-level-connected-rooms (car dimensions) (cadr dimensions))))
	  (for-each-index
	   (car dimensions)
	   (cadr dimensions)
	   (lambda (row col)
	     (case (array-ref tile-info row col)
	       ((0) ($ level 'set-square! row col (instance Wall)))
	       ((3) ($ level 'set-square! row col (instance Floor)))
	       ((4) ($ level 'set-square! row col 
		       (instance (if (= 0 (random 2)) OpenDoor ClosedDoor))))
	       ((2) ($ level 'set-square! row col (instance RoomWall)))
	       ((1) ($ level 'set-square! row col (instance RoomFloor))))
	     (set! ($ level `(player-memory (,row ,col))) (instance Memory))))
	  (let ((weights 
		 (map 
		  (lambda (el) (list (car el) (prob (caddr el) depth (cadr el)))) 
		  (filter 
		   (lambda (el) (not (eq? (cadr el) 'never))) 
		   (leaf-object-map 
		    Agent
		    (lambda (obj) 
		      (list (object-name obj) ($ obj 'rarity) ($ obj 'level)))))))
		(agent-count 1))
	    (for-each 
	     (lambda (n)
	       (let pick 
		   ((sum 0) (lst weights) (guess (random (fold + 0 (map cadr weights)))))
		 (if (<= guess (+ sum (cadar lst)))
		     ($ level 'insert-agent (instance (cons Agent (caar lst)) #:args '()))
		     (pick (+ sum (cadar lst)) (cdr lst) guess))))
		      (iota agent-count)))
	  (if (< depth (- ($ this 'depth) 1))
	      (set! 
	       ($ level 
		  `(squares 
		    ,($ level 'random-location 
			(lambda (square location) ($ square 'room-floor? #:def #f )))))
		    (instance DownStair)))
	  (set! ($ level 
		   `(squares 
		     ,($ level 'random-location 
			 (lambda (square location) (square #:def #f 'room-floor?)))))
		(instance UpStair))
	  level))))

(define-objects Dungeon
  ((initialize! (method (name depth)
		  (set! ($ this 'depth) depth)
		  (set! ($ this 'name) name)
		  (set! ($ this 'level-cache) (make-vector depth #f))))
   (get-level 
    (method (n) (or (vector-ref ($ this 'level-cache) n) ($ this 'make-level n))))
   (cache-level 
    (method (level env) 
      (set! ($ level 'visibility) #f)
      (set! ($ level 'lighting) #f)
      (vector-set! ($ this 'level-cache) (level 'depth) (object-compile level env)))))
  ((StandardDungeon
    ((make-level make-standard-level)))))

(define (make-weights level)
  (let* ((dimensions (array-dimensions level)) 
         (weights (apply make-array `(0 ,@dimensions))))
    (for-each-index
      (car dimensions)
      (cadr dimensions)
      (lambda (row col)
        (array-set! weights 
                    (if (or (= 0 row) (= 0 col) (= 19 row) (= 79 col)) 
                      10000
                      (case (array-ref level row col) 
                        ((0) 20) 
                        ((2) 1000)
                        ((1) 10))) row col)))
    weights))

(define (for-tiles-in-path proc weights start end)
  (let ((paths (dijkstra weights end #f)))
    (let do-next ((current start))
      (proc (car current) (cadr current))
      (if (not (equal? current end))
        (do-next (array-ref paths (car current) (cadr current)))))))

(define make-level-connected-rooms
  (letrec* 
    ((directions '(left right up down))
     (get-top car) (get-left cadr) (get-height caddr) (get-width cadddr)
     (mappings '((left . (up-left left down-left))
                 (right . (up-right right down-right))
                 (up . (up-left up up-right))
                 (down . (down-left down down-right))))
     (octants '(up-left up up-right left right down-left down down-right))
     (all-quadrants '(up down left right up-left up-right down-left down-right))
     (get-available-octants 
      (lambda (direction available)
	(lset-intersection eq? (cdr (assoc direction mappings)) available)))
     (octant-dimensions 
      (lambda (octant area room)
	(let ((up-height (delay (- (get-top room) (get-top area))))
	      (left-width (delay (- (get-left room) (get-left area))))
	      (right-left (delay (+ (get-left room) (get-width room))))
	      (right-width 
	       (delay (- (get-width area) (get-width room) 
			 (- (get-left room) (get-left area)))))
	      (down-height 
	       (delay (- (get-height area) (get-height room) 
			 (- (get-top room) (get-top area)))))
	      (down-top (delay (+ (get-top room) (get-height room)))))
	  (case octant
	    ((up) 
	     (list (get-top area) (get-left room) (force up-height) (get-width room)))
	    ((left) 
	     (list (get-top room) (get-left area) (get-height room) (force left-width)))
	    ((right) 
	     (list (get-top room) (force right-left) 
		   (get-height room) (force right-width)))
	    ((down) 
	     (list (force down-top) (get-left room) 
		   (force down-height) (get-width room)))
	    ((up-left) 
	     (list (get-top area) (get-left area) 
		   (force up-height) (force left-width)))
	    ((up-right) 
	     (list (get-top area) (force right-left) 
		   (force up-height) (force right-width)))
	    ((down-left) 
	     (list (force down-top) (get-left area) 
		   (force down-height) (force left-width)))
	    ((down-right) 
	     (list (force down-top) (force right-left) 
		   (force down-height) (force right-width)))))))
     (merge-octants 
      (lambda (octants) 
	(fold 
	 (lambda (to-merge merged)
	   (list
	    (min (get-top to-merge) (get-top merged))
	    (min (get-left to-merge) (get-left merged))
	    (if (= (get-top to-merge) (get-top merged))
		(get-height to-merge) 
		(+ (get-height to-merge) (get-height merged)))
	    (if (= (get-left to-merge) (get-left merged)) 
		(get-width to-merge) 
		(+ (get-width to-merge) (get-width merged))))) 
	 (car octants) (cdr octants))))
     (insert-room 
      (lambda (level area directions)
	(if (and (> (get-height area) 4) (> (get-width area) 6))
	    (let* 
		((center-row (+ (get-top area) 1 (random (- (get-height area) 1))))
		 (center-col (+ (get-left area) 3 (random (- (get-width area) 3))))
		 (possible-height (+ 4 (random 5)))
		 (possible-width (+ 6 (random 18)))
		 (new-top 
		  (max (get-top area) (- center-row (quotient possible-height 2))))
		 (new-left 
		  (max (get-left area) (- center-col (quotient possible-width 2))))
		 (new-height 
		  (- (min (+ new-top possible-height) 
			  (- (+ (get-top area) (get-height area)) 1))
		     new-top))
		 (new-width 
		  (- (min (+ new-left possible-width)
			  (- (+ (get-left area) (get-width area)) 1)) 
		     new-left)))
	      (let ((make-new-room? 
		     (and (> new-height 4) (> new-width 6) (> (random 8) 0)))
		    (other-rooms 
		     (fill-sides 
		      level 
		      (if (or (eq? (car directions) 'left) 
			      (eq? (car directions) 'right))
			  '(up down left right) '(right left up down)) 
		      all-quadrants 
		      area 
		      (list new-top new-left new-height new-width))))
		(if make-new-room?
		    (begin 
		      (for-each 
		       (lambda (row)
			 (for-each 
			  (lambda (col)
			    (if 
			     (or (= new-top row) 
				 (= (- (+ new-top new-height) 1) row)
				 (= (+ 1 new-left) col)
				 (= (- (+ new-left new-width) 1) col))
				(array-set! level 2 row col)
				(array-set! level 1 row col)))
				   (map 
				    (lambda (n) (+ 1 n new-left)) (iota (- new-width 1)))))
				     (map (lambda (n) (+ n new-top)) (iota new-height)))
			   (append 
			    (list 
			     (list (+ new-top 1 (random (- new-height 2)))
				   (+ new-left 1 (random (- new-width 2))))) 
			    other-rooms)) other-rooms)))
	    #f)))
     (fill-sides 
      (lambda (level directions available area room)
	(if (not (null? directions))
	    (let* ((dir (car directions))
		   (octants (get-available-octants dir available))
		   (fill-dimensions 
		    (merge-octants 
		     (map (lambda (octant) (octant-dimensions octant area room)) octants)))
		   (new-rooms (insert-room level fill-dimensions directions))
		   (all-new-rooms 
		    (fill-sides 
		     level 
		     (delq dir directions)
		     (if new-rooms 
			 (lset-difference eq? available octants) available) area room)))
	      (append all-new-rooms (if new-rooms new-rooms '())))
	    '()))))
    (lambda (rows cols)
      (let generate ((level (make-array 0 rows cols)))
        (let ((rooms (insert-room level (list 0 0 rows cols) '(left right))))
          (if (< (length rooms) 7)
            (generate (make-array 0 rows cols))
            (begin
              (let ((links 
		     (pair-fold (lambda (par tot) 
				  (if (> (length par) 1)
				      (cons (list (car par) (cadr par)) tot)
				      (cons (list (car par) (car rooms)) tot))) '() rooms))
                    (weights (make-weights level)))
                (par-for-each (lambda (link) (for-tiles-in-path 
                                               (lambda (row col) 
                                                 (case (array-ref level row col) 
						   ((0) (array-set! level 3 row col))
						   ((2) (array-set! level 4 row col))))
					       weights (car link) (cadr link))) links)
                level))))))))

(define 
  (prob native-depth current-depth rarity)
  (let ((base-prob (/ 1 (expt e (abs (- native-depth current-depth))))))
    (case rarity
      ((common) base-prob)
      ((rare) (/ base-prob 3))
      ((very-rare) (/ base-prob 10)))))
