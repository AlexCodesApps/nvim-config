#!r6rs

(import (chezscheme))

(define (u64->bytevector n endian)
  (let ([bv (make-bytevector 8)])
    (bytevector-u64-set! bv 0 n endian)
    bv))

(define transcoder (make-transcoder (utf-8-codec)))

(define (utf8->bytevector utf8)
  (string->bytevector utf8 transcoder))

(define (send-message bv stdout)
  (let ([bvlen (bytevector-length bv)])
    (put-bytevector stdout (u64->bytevector bvlen (endianness big)))
    (put-bytevector stdout bv))
    (flush-output-port stdout))

(define (send-message-utf8 utf8 stdout)
  (send-message (utf8->bytevector utf8) stdout))

(define (recv-message stdin stdout)
  (let* ([bvlen (get-bytevector-n stdin 8)]
         [payload #f])
    (if (not (eq? (bytevector-length bvlen) 8))
        (begin
              (send-message-utf8 "error: unexpected EOF" stdout)
                            #f)
        (begin
              (set! bvlen (bytevector-u64-ref bvlen 0 (endianness big)))
              (set! payload (get-bytevector-n stdin bvlen))
              (if (not (eq? (bytevector-length payload) bvlen))
                  (begin
                    (send-message-utf8 "error: unexpected EOF"  stdout)
                    #f)
                  payload)))))

(define (recv-message-utf8 stdin stdout)
  (let ([msg (recv-message stdin stdout)])
    (if msg
      (bytevector->string msg transcoder)
      #f)))

(define (expr->string e)
  (call-with-string-output-port
   (lambda (out) (write e out))))

(define (error->string err)
  (string-append
   "ERROR: "
   (if (message-condition? err)
       (condition-message err) (expr->string err))))

(define (eval-expr->string code)
  (call/cc
   (lambda (k)
     (with-exception-handler
	 (lambda (err)
	   (k (string-append
	       "ERROR: "
	       (if (message-condition? err)
		   (condition-message err) (expr->string err)))))
       (lambda ()
	 (expr->string (eval code (interaction-environment))))))))

(define stdin (standard-input-port))
(define stdout (standard-output-port))

(define (loop)
  (let* ([msg (recv-message-utf8 stdin stdout)]
         [code (read (open-input-string msg))])
  (send-message-utf8 (eval-expr->string code) stdout)))

(define (main)
  (guard
    (err [else (send-message-utf8 (error->string err) stdout)])
    (loop))
  (main))

(main)
