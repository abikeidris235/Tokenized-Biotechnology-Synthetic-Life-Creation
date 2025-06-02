;; Ethical Oversight Contract
;; Ensures research meets ethical standards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-review-not-found (err u401))
(define-constant err-not-authorized (err u402))
(define-constant err-ethics-violation (err u403))
(define-constant err-review-pending (err u404))

;; Data Variables
(define-data-var next-review-id uint u1)
(define-data-var next-committee-id uint u1)

;; Data Maps
(define-map ethics-reviews
  { review-id: uint }
  {
    protocol-id: uint,
    reviewer: principal,
    review-status: (string-ascii 20), ;; "pending", "approved", "rejected"
    review-notes: (string-ascii 500),
    submitted-at: uint,
    reviewed-at: uint
  }
)

(define-map ethics-committee
  { committee-id: uint }
  {
    member: principal,
    specialty: (string-ascii 100),
    active: bool,
    appointed-at: uint
  }
)

(define-map protocol-ethics-status
  { protocol-id: uint }
  {
    status: (string-ascii 20), ;; "pending", "approved", "rejected"
    reviews-required: uint,
    reviews-completed: uint,
    approval-date: uint
  }
)

(define-map ethics-violations
  { violation-id: uint }
  {
    protocol-id: uint,
    violation-type: (string-ascii 100),
    description: (string-ascii 500),
    reported-by: principal,
    severity: uint,
    reported-at: uint
  }
)

(define-data-var next-violation-id uint u1)

;; Public Functions

;; Submit protocol for ethics review
(define-public (submit-for-ethics-review (protocol-id uint))
  (let
    (
      (review-id (var-get next-review-id))
    )
    (map-set ethics-reviews
      { review-id: review-id }
      {
        protocol-id: protocol-id,
        reviewer: tx-sender,
        review-status: "pending",
        review-notes: "",
        submitted-at: block-height,
        reviewed-at: u0
      }
    )

    (map-set protocol-ethics-status
      { protocol-id: protocol-id }
      {
        status: "pending",
        reviews-required: u3, ;; Require 3 reviews
        reviews-completed: u0,
        approval-date: u0
      }
    )

    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

;; Complete ethics review (committee member only)
(define-public (complete-ethics-review
  (review-id uint)
  (status (string-ascii 20))
  (notes (string-ascii 500)))
  (let
    (
      (review (unwrap! (map-get? ethics-reviews { review-id: review-id }) err-review-not-found))
      (protocol-id (get protocol-id review))
      (current-status (unwrap! (map-get? protocol-ethics-status { protocol-id: protocol-id }) err-review-not-found))
    )
    ;; Check if reviewer is committee member
    (asserts! (is-committee-member tx-sender) err-not-authorized)

    (map-set ethics-reviews
      { review-id: review-id }
      (merge review {
        review-status: status,
        review-notes: notes,
        reviewed-at: block-height
      })
    )

    ;; Update protocol status
    (let
      (
        (completed-reviews (+ (get reviews-completed current-status) u1))
        (required-reviews (get reviews-required current-status))
      )
      (map-set protocol-ethics-status
        { protocol-id: protocol-id }
        (merge current-status {
          reviews-completed: completed-reviews,
          status: (if (>= completed-reviews required-reviews) "approved" "pending"),
          approval-date: (if (>= completed-reviews required-reviews) block-height u0)
        })
      )
    )

    (ok true)
  )
)

;; Add committee member (owner only)
(define-public (add-committee-member (member principal) (specialty (string-ascii 100)))
  (let
    (
      (committee-id (var-get next-committee-id))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set ethics-committee
      { committee-id: committee-id }
      {
        member: member,
        specialty: specialty,
        active: true,
        appointed-at: block-height
      }
    )
    (var-set next-committee-id (+ committee-id u1))
    (ok committee-id)
  )
)

;; Report ethics violation
(define-public (report-ethics-violation
  (protocol-id uint)
  (violation-type (string-ascii 100))
  (description (string-ascii 500))
  (severity uint))
  (let
    (
      (violation-id (var-get next-violation-id))
    )
    (map-set ethics-violations
      { violation-id: violation-id }
      {
        protocol-id: protocol-id,
        violation-type: violation-type,
        description: description,
        reported-by: tx-sender,
        severity: severity,
        reported-at: block-height
      }
    )
    (var-set next-violation-id (+ violation-id u1))
    (ok violation-id)
  )
)

;; Read-only Functions

;; Get ethics review
(define-read-only (get-ethics-review (review-id uint))
  (map-get? ethics-reviews { review-id: review-id })
)

;; Get protocol ethics status
(define-read-only (get-protocol-ethics-status (protocol-id uint))
  (map-get? protocol-ethics-status { protocol-id: protocol-id })
)

;; Check if protocol is ethically approved
(define-read-only (is-protocol-ethically-approved (protocol-id uint))
  (match (map-get? protocol-ethics-status { protocol-id: protocol-id })
    status (is-eq (get status status) "approved")
    false
  )
)

;; Check if address is committee member
(define-read-only (is-committee-member (member principal))
  (let
    (
      (committee-id u1) ;; Simplified check - in practice would iterate
    )
    (match (map-get? ethics-committee { committee-id: committee-id })
      committee-data (and (is-eq (get member committee-data) member) (get active committee-data))
      false
    )
  )
)

;; Get ethics violation
(define-read-only (get-ethics-violation (violation-id uint))
  (map-get? ethics-violations { violation-id: violation-id })
)
