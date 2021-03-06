#lang planet neil/sicp

(define (remove v ls)
  (cond ((null? ls) '())
        ((equal? v (car ls)) (remove v (cdr ls)))
        (else (cons (car ls) (remove v (cdr ls))))))

(define apply-in-underlying-scheme apply)

;; -------------------------------------------------------
;; The Metacircular Evaluator, p.364
;; -------------------------------------------------------

(define (eval exp env)
  ((analyze exp) env))

(define (analyze exp)
  (cond ((self-evaluating? exp)
         (analyze-self-evaluating exp))
        ((variable? exp) (analyze-variable exp))
        ((quoted? exp) (analyze-quoted exp))
        ((assignment? exp) (analyze-assignment exp))
        ((definition? exp) (analyze-definition exp))
        ((unbind? exp) (analyze-unbind exp))
        ((if? exp) (analyze-if exp))
        ((and? exp) (analyze (and->if exp)))
        ((or? exp) (analyze (or->if exp)))
        ((lambda? exp) (analyze-lambda exp))
        ((let? exp) (analyze (let->combination exp)))
        ((let*? exp) (analyze (let*->nested-lets exp)))
        ((letrec? exp) (analyze (letrec->let exp)))
        ((begin? exp) (analyze-sequence (begin-actions exp)))
        ((cond? exp) (analyze (cond->if exp)))
        ((application? exp) (analyze-application exp))
        (else
         (error "Unknown expression type -- EVAL" exp))))

;; Exercise 4.1, p.368
;; Operands evaluation order

(define (list-of-values exps env)
  (if (no-operands? exps)
      '()
      ; Swap 'first' and 'rest' to make evaluation left-to-right
      (let* ((rest (list-of-values (rest-operands exps) env))
             (first (eval (first-operand exps) env)))
        (cons first rest))))

;(list-of-values (list 1 2 3) nil)

;; -------------------------------------------------------
;; Representing Expressions, p.368
;; -------------------------------------------------------

(define (tagged-list? exp tag)
  (and (pair? exp) (eq? (car exp) tag)))

(define (self-evaluating? exp)
  (or (number? exp) (string? exp)))

(define (variable? exp) (symbol? exp))

(define (quoted? exp) (tagged-list? exp 'quote))
(define (text-of-quotation exp) (cadr exp))

(define (assignment? exp) (tagged-list? exp 'set!))
(define (assignment-variable exp) (cadr exp))
(define (assignment-value exp) (caddr exp))

(define (definition? exp)
  (tagged-list? exp 'define))

(define (definition-variable exp)
  (if (symbol? (cadr exp))
      (cadr exp)
      (caadr exp)))

(define (definition-value exp)
  (if (symbol? (cadr exp))
      (caddr exp)
      (make-lambda (cdadr exp) (cddr exp))))

(define (lambda? exp) (tagged-list? exp 'lambda))
(define (lambda-parameters exp) (cadr exp))
(define (lambda-body exp) (cddr exp))
(define (make-lambda parameters body)
  (cons 'lambda (cons parameters body)))

(define (if? exp) (tagged-list? exp 'if))
(define (if-predicate exp) (cadr exp))
(define (if-consequent exp) (caddr exp))

(define (if-alternative exp)
  (if (not (null? (cdddr exp)))
      (cadddr exp)
      'false))

(define (make-if predicate consequent alternative)
  (list 'if predicate consequent alternative))

(define (begin? exp) (tagged-list? exp 'begin))
(define (begin-actions exp) (cdr exp))

(define (last-exp? seq) (null? (cdr seq)))
(define (first-exp seq) (car seq))
(define (rest-exps seq) (cdr seq))

(define (sequence->exp seq)
  (cond ((null? seq) seq)
        ((last-exp? seq) (first-exp seq))
        (else (make-begin seq))))

(define (make-begin seq) (cons 'begin seq))

(define (application? exp) (pair? exp))
(define (operator exp) (car exp))
(define (operands exp) (cdr exp))
(define (no-operands? ops) (null? ops))
(define (first-operand ops) (car ops))
(define (rest-operands ops) (cdr ops))

(define (cond? exp) (tagged-list? exp 'cond))
(define (cond-clauses exp) (cdr exp))

(define (cond-else-clause? clause)
  (eq? (cond-predicate clause) 'else))

(define (cond-predicate clause) (car clause))

(define (cond-actions clause) (cdr clause))

(define (cond->if exp)
  (expand-clauses (cond-clauses exp)))

(define (expand-clauses clauses)
  (if (null? clauses)
      'false
      (let ((first (car clauses))
            (rest (cdr clauses)))
        (if (cond-else-clause? first)
            (if (null? rest)
                (sequence->exp (cond-actions first))
                (error "ELSE clause isn't last -- COND->IF" clauses))
            (make-if (cond-predicate first)
                     (sequence->exp (cond-actions first))
                     (expand-clauses rest))))))

;; Exercise 4.4, p.374

(define (and? exp) (tagged-list? exp 'and))
(define (and->if exp) (expand-and-operands (operands exp)))

(define (expand-and-operands ops)
  (if (no-operands? ops)
      'true
      (make-if (first-operand ops)
               (expand-and-operands (rest-operands ops))
               'false)))

(define (or? exp) (tagged-list? exp 'or))
(define (or->if exp) (expand-or-operands (operands exp)))

(define (expand-or-operands ops)
  (if (no-operands? ops)
      'false
      (make-if (first-operand ops)
               'true
               (expand-or-operands (rest-operands ops)))))

;; Exercise 4.6, p.375

(define (let? exp) (tagged-list? exp 'let))
(define (let-vars exp) (map car (cadr exp)))
(define (let-vals exp) (map cadr (cadr exp)))
(define (let-body exp) (cddr exp))

(define (let->combination exp)
  (cons (make-lambda (let-vars exp) (let-body exp))
        (let-vals exp)))

;; Exercise 4.7, p.375

(define (let*? exp) (tagged-list? exp 'let*))

(define (let*->nested-lets exp)
  (let ((let-bindings (cadr exp))
        (let-body (caddr exp)))
    (define (expand-let-bindings bindings)
      (if (null? bindings)
          let-body
          (list 'let
                (list (car bindings))
                (expand-let-bindings (cdr bindings)))))
    (expand-let-bindings let-bindings)))

;; -------------------------------------------------------
;; Evaluator Data Structures, p.376
;; -------------------------------------------------------

(define (false? x) (eq? x false))
(define (true? x) (not (false? x)))

(define (make-procedure parameters body env)
  (list 'procedure parameters body env))

(define (compound-procedure? p)
  (tagged-list? p 'procedure))

(define (procedure-parameters p) (cadr p))
(define (procedure-body p) (caddr p))
(define (procedure-environment p) (cadddr p))

(define (enclosing-environment env) (cdr env))
(define (first-frame env) (car env))
(define the-empty-environment '())

;; Exercise 4.11, p.380

(define (make-frame variables values)
  (cons 'frame (map cons variables values)))

(define (frame-bindings frame) (cdr frame))

(define (add-binding-to-frame! var val frame)
  (set-cdr! frame (cons (cons var val)
                        (frame-bindings frame))))

(define (extend-environment vars vals base-env)
  (if (= (length vars) (length vals))
      (cons (make-frame vars vals) base-env)
      (if (< (length vars) (length vals))
          (error "Too many arguments supplied" vars vals)
          (error "Too few arguments supplied" vars vals))))

;; Exercise 4.12, p.380

(define ((set-val! val) var) (set-cdr! var val))

(define (do-in-frame var frame then-proc else-proc)
  (let ((binding (assoc var (frame-bindings frame))))
    (if binding
        (then-proc binding)
        (else-proc binding))))

(define (env-loop var env action)
  (if (eq? env the-empty-environment)
      (error "Unbound variable" var)
      (let ((frame (first-frame env))
            (try-next-frame
             (lambda (_)
               (env-loop var (enclosing-environment env) action))))
        (do-in-frame var frame action try-next-frame))))

(define (lookup-variable-value var env)
  (env-loop var env cdr))

(define (set-variable-value! var val env)
  (env-loop var env (set-val! val)))

(define (define-variable! var val env)
  (let* ((frame (first-frame env))
         (bind (lambda (_)
                 (add-binding-to-frame! var val frame))))
  (do-in-frame var frame (set-val! val) bind)))

;; Exercise 4.13, p.380

(define (unbind? exp) (tagged-list? exp 'forget))
(define (unbind-var exp) (cadr exp))

(define (unbind-variable! var env)
  (let* ((frame (first-frame env))
         (unbind
          (lambda (binding)
            (set-cdr! frame (remove binding (frame-bindings frame))))))
    (do-in-frame var frame unbind identity)))

;; -------------------------------------------------------
;; Running Evaluator, p.381
;; -------------------------------------------------------

(define primitive-procedures
  (list (list 'car car)
        (list 'cdr cdr)
        (list 'cons cons)
        (list 'null? null?)
        (list '= =)
        (list '< <)
        (list '+ +)
        (list '- -)
        (list '* *)))

(define (primitive-procedure-names)
  (map car primitive-procedures))

(define (primitive-procedure-objects)
  (map (lambda (proc) (list 'primitive (cadr proc)))
       primitive-procedures))

(define (setup-environment)
  (let ((initial-env
         (extend-environment (primitive-procedure-names)
                             (primitive-procedure-objects)
                             the-empty-environment)))
    (define-variable! 'true true initial-env)
    (define-variable! 'false false initial-env)
    (define-variable! '*unassigned* '*unassigned* initial-env)
    initial-env))

(define the-global-environment (setup-environment))

(define (primitive-procedure? proc)
  (tagged-list? proc 'primitive))

(define (primitive-implementation proc) (cadr proc))

(define (apply-primitive-procedure proc args)
  (apply-in-underlying-scheme
   (primitive-implementation proc) args))

(define input-prompt ";;; M-Eval input:")
(define output-prompt ";;; M-Eval value:")

(define (driver-loop)
  (prompt-for-input input-prompt)
  (let* ((input (read))
         (output (eval input the-global-environment)))
    (announce-output output-prompt)
    (user-print output))
  (driver-loop))

(define (prompt-for-input string)
  (newline) (newline) (display string) (newline))

(define (announce-output string)
  (newline) (display string) (newline))

(define (user-print object)
  (if (compound-procedure? object)
      (display (list 'compound-procedure
                     (procedure-parameters object)
                     (procedure-body object)
                     '<procedure-env>))
      (display object)))

;; -------------------------------------------------------
;; Syntactic Analysis, p.393
;; -------------------------------------------------------

(define (analyze-self-evaluating exp)
  (lambda (env) exp))

(define (analyze-variable exp)
  (lambda (env) (lookup-variable-value exp env)))

(define (analyze-quoted exp)
  (let ((qval (text-of-quotation exp)))
    (lambda (env) qval)))

(define (analyze-assignment exp)
  (let ((var (assignment-variable exp))
        (vproc (analyze (assignment-value exp))))
    (lambda (env)
      (set-variable-value! var (vproc env) env)
      'ok)))

(define (analyze-definition exp)
  (let ((var (definition-variable exp))
        (vproc (analyze (definition-value exp))))
    (lambda (env)
      (define-variable! var (vproc env) env)
      'ok)))

(define (analyze-unbind exp)
  (let ((var (unbind-var exp)))
    (lambda (env)
      (unbind-variable! var env)
      'ok)))

(define (analyze-if exp)
  (let ((pproc (analyze (if-predicate exp)))
        (cproc (analyze (if-consequent exp)))
        (aproc (analyze (if-alternative exp))))
    (lambda (env)
      (if (true? (pproc env))
          (cproc env)
          (aproc env)))))

(define (analyze-lambda exp)
  (let ((vars (lambda-parameters exp))
        (bproc (analyze-sequence (lambda-body exp))))
    (lambda (env) (make-procedure vars bproc env))))

(define (analyze-sequence exps)
  (define (sequentially proc1 proc2)
    (lambda (env) (proc1 env) (proc2 env)))
  (define (loop first-proc rest-procs)
    (if (null? rest-procs)
        first-proc
        (loop (sequentially first-proc (car rest-procs))
              (cdr rest-procs))))
  (let ((procs (map analyze exps)))
    (if (null? procs)
        (error "Empty sequence -- ANALYZE"))
    (loop (car procs) (cdr procs))))

(define (analyze-application exp)
  (let ((fproc (analyze (operator exp)))
        (aprocs (map analyze (operands exp))))
    (lambda (env)
      (execute-application (fproc env)
                           (map (lambda (aproc) (aproc env))
                                aprocs)))))

(define (execute-application proc args)
  (cond ((primitive-procedure? proc)
         (apply-primitive-procedure proc args))
        ((compound-procedure? proc)
         ((procedure-body proc)
          (extend-environment (procedure-parameters proc)
                              args
                              (procedure-environment proc))))
        (else
         (error "Unknown procedure type -- EXECUTE-APPLICATION" proc))))

;; -------------------------------------------------------
;; Exercises
;; -------------------------------------------------------

;; Exercise 4.2.b, p.374

;(define (application? exp) (tagged-list? exp 'call))
;(define (operator exp) (cadr exp))
;(define (operands exp) (cddr exp))

;; Exercise 4.20, p.391

(define (letrec? exp) (tagged-list? exp 'letrec))
(define (letrec-bindings exp) (cadr exp))
(define (letrec-body exp) (cddr exp))
(define (letrec-declarations exp)
  (map (lambda (b) (list (car b) '*unassigned*))
       (letrec-bindings exp)))
(define (letrec-sets exp)
  (map (lambda (b) (list 'set! (car b) (cadr b)))
       (letrec-bindings exp)))

(define (letrec->let exp)
  (append (list 'let (letrec-declarations exp))
          (letrec-sets exp)
          (letrec-body exp)))

(driver-loop)

;> (define x 5)
;> (set! x 6)
;> (let* ((x 3) (y (+ x 2)) (z (+ x y 5))) (* x z))
;> (forget x)
;> (define (append x y) (if (null? x) y (cons (car x) (append (cdr x) y))))
;> (append '(a b c) '(d e f))
;> (define (f) (letrec ((fact (lambda (n) (if (= n 1) 1 (* n (fact (- n 1))))))) (fact 10)))
;> (f)

;; Exercise 4.21, p.392
;; Y-combinator hurts my brain!

((lambda (n)
   ((lambda (fact)
      (fact fact n))
    (lambda (ft k)
      (if (= k 1)
          1
          (* k (ft ft (- k 1)))))))
 10)

((lambda (n)
   ((lambda (fib)
      (fib fib n))
    (lambda (fb k)
      (cond ((= k 0) 0)
            ((= k 1) 1)
            (else (+ (fb fb (- k 1))
                     (fb fb (- k 2))))))))
 10)

(define (f x)
  ((lambda (even? odd?)
     (even? even? odd? x))
   (lambda (ev? od? n)
     (if (= n 0) true (od? ev? od? (- n 1))))
   (lambda (ev? od? n)
     (if (= n 0) false (ev? ev? od? (- n 1))))))

(f 4)
(not (f 5))

;; Exercise 4.24, p.398

(define fibs
  (list 'define (list 'fib 'n)
        (list 'if (list '< 'n 3)
              1
              (list '+
                    (list 'fib (list '- 'n 1))
                    (list 'fib (list '- 'n 2))))))

(define start (runtime))
(eval fibs the-global-environment)
(eval (list 'fib 30) the-global-environment)
(/ (- (runtime) start) 1e6) ;= ~8 seconds
