;; ===========================================
;; Multicast Standard - Governance Contract
;; ===========================================
;; This contract manages a decentralized governance system for distributed decision-making
;; using a flexible, secure multicast voting mechanism. It provides a standardized
;; approach to proposal creation, voting, and execution across various use cases.

;; ===========================================
;; Error Constants
;; ===========================================
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-MEMBER (err u101))
(define-constant ERR-NOT-MEMBER (err u102))
(define-constant ERR-INSUFFICIENT-TOKENS (err u103))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u104))
(define-constant ERR-INVALID-PROPOSAL-STATE (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-VOTING-CLOSED (err u107))
(define-constant ERR-PROPOSAL-ACTIVE (err u108))
(define-constant ERR-INVALID-AMOUNT (err u109))
(define-constant ERR-MILESTONE-NOT-FOUND (err u110))
(define-constant ERR-MILESTONE-ALREADY-FUNDED (err u111))
(define-constant ERR-DELEGATION-NOT-ALLOWED (err u112))
(define-constant ERR-INVALID-PHASE (err u113))
(define-constant ERR-TREASURY-INSUFFICIENT-FUNDS (err u114))

;; ===========================================
;; Proposal States and Phases
;; ===========================================
(define-constant PROPOSAL-STATE-DRAFT u0)
(define-constant PROPOSAL-STATE-ACTIVE u1)
(define-constant PROPOSAL-STATE-PASSED u2)
(define-constant PROPOSAL-STATE-REJECTED u3)
(define-constant PROPOSAL-STATE-EXECUTED u4)
(define-constant PROPOSAL-STATE-CANCELLED u5)

(define-constant PHASE-SUBMISSION u0)
(define-constant PHASE-DISCUSSION u1)
(define-constant PHASE-VOTING u2)
(define-constant PHASE-EXECUTION u3)

;; ===========================================
;; Data Maps and Variables
;; ===========================================
;; Member data - tracks token balance and member status
(define-map members principal { 
  token-balance: uint, 
  is-active: bool, 
  joined-at: uint,
  delegated-to: (optional principal),
  is-expert: bool
})

;; Governance proposal data
(define-map proposals uint {
  title: (string-ascii 100),
  description: (string-utf8 1000),
  link: (string-ascii 255),
  proposer: principal,
  created-at: uint,
  funding-amount: uint,
  state: uint,
  current-phase: uint,
  phase-end-time: uint,
  yes-votes: uint,
  no-votes: uint,
  executed-at: (optional uint),
  milestones: (list 10 {
    description: (string-utf8 200),
    amount: uint,
    completed: bool,
    funded: bool
  })
})

;; Track member voting records for each proposal
(define-map proposal-votes { proposal-id: uint, voter: principal } {
  vote: bool,
  weight: uint,
  voted-at: uint
})

;; Track quadratic voting weights used by each member in a proposal
(define-map quadratic-voting-used { proposal-id: uint, voter: principal } uint)

;; Treasury information
(define-data-var treasury-balance uint u0)
(define-data-var total-tokens-issued uint u0)

;; Proposal counter
(define-data-var proposal-counter uint u0)

;; Governance settings
(define-data-var submission-phase-length uint u86400) ;; 24 hours in seconds
(define-data-var discussion-phase-length uint u259200) ;; 3 days in seconds
(define-data-var voting-phase-length uint u259200) ;; 3 days in seconds
(define-data-var execution-delay uint u43200) ;; 12 hours in seconds
(define-data-var quorum-threshold uint u100) ;; Minimum votes required as percentage of total tokens
(define-data-var proposal-acceptance-threshold uint u60) ;; Percentage of Yes votes required to pass

;; ===========================================
;; Private Functions
;; ===========================================

;; Check if caller is a member
(define-private (is-member (caller principal))
  (default-to false (get is-active (map-get? members caller))))

;; Get member token balance
(define-private (get-member-balance (user principal))
  (default-to u0 (get token-balance (map-get? members user))))

;; Advance proposal to next phase
(define-private (advance-proposal-phase (proposal-id uint) (new-phase uint) (phase-duration uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (new-end-time (+ block-height phase-duration))
  )
    (map-set proposals proposal-id 
      (merge proposal {
        current-phase: new-phase,
        phase-end-time: new-end-time
      })
    )
    (ok true)
  ))

;; Calculate quadratic voting weight based on tokens
(define-private (calculate-quadratic-weight (tokens uint))
  ;; Taking the square root - approximated in clarity
  ;; Note: This is a simplified approximation for demo purposes
  ;; A more precise implementation would be needed in production
  (+ u1 (/ tokens u10)))

;; Check if proposal exists and is in specified state
(define-private (is-proposal-in-state (proposal-id uint) (expected-state uint))
  (match (map-get? proposals proposal-id)
    proposal (is-eq (get state proposal) expected-state)
    false))

;; Check if proposal is in specified phase
(define-private (is-proposal-in-phase (proposal-id uint) (expected-phase uint))
  (match (map-get? proposals proposal-id)
    proposal (is-eq (get current-phase proposal) expected-phase)
    false))

;; Check if proposal voting period is active
(define-private (is-voting-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and 
              (is-eq (get current-phase proposal) PHASE-VOTING)
              (<= block-height (get phase-end-time proposal)))
    false))

;; Transfer funds to a proposal recipient for a milestone
(define-private (fund-milestone (proposal-id uint) (milestone-index uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (milestones (get milestones proposal))
    (milestone (unwrap! (element-at milestones milestone-index) ERR-MILESTONE-NOT-FOUND))
  )
    ;; Check if milestone is already funded
    (asserts! (not (get funded milestone)) ERR-MILESTONE-ALREADY-FUNDED)
    
    ;; Check treasury has sufficient funds
    (asserts! (>= (var-get treasury-balance) (get amount milestone)) ERR-TREASURY-INSUFFICIENT-FUNDS)
    
    ;; Update treasury balance
    (var-set treasury-balance (- (var-get treasury-balance) (get amount milestone)))
    
    ;; Update milestone as funded
    ;; (map-set milestones milestone-index (merge milestone { funded: true }))
    (ok true)
  ))

;; ===========================================
;; Read-Only Functions
;; ===========================================

;; Get member information
(define-read-only (get-member (member-principal principal))
  (map-get? members member-principal))

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id))

;; Get member's vote on a specific proposal
(define-read-only (get-member-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter }))

;; Get treasury balance
(define-read-only (get-treasury-balance)
  (var-get treasury-balance))

;; Get total tokens issued
(define-read-only (get-total-tokens)
  (var-get total-tokens-issued))

;; Get proposal count
(define-read-only (get-proposal-count)
  (var-get proposal-counter))

;; Check if proposal has reached quorum
(define-read-only (has-reached-quorum (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal 
      (let (
        (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
        (min-required-votes (/ (* (var-get total-tokens-issued) (var-get quorum-threshold)) u100))
      )
        (>= total-votes min-required-votes))
    false))

;; Check if proposal has passed
(define-read-only (has-proposal-passed (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal 
      (let (
        (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
        (yes-percentage (if (is-eq total-votes u0) 
                          u0 
                          (/ (* (get yes-votes proposal) u100) total-votes)))
      )
        (and 
          (has-reached-quorum proposal-id)
          (>= yes-percentage (var-get proposal-acceptance-threshold))))
    false))

;; ===========================================
;; Public Functions
;; ===========================================

;; Register as a new member with initial token allocation
(define-public (register-member (token-amount uint) (is-expert bool))
  (let (
    (caller tx-sender)
  )
    ;; Ensure caller is not already a member
    (asserts! (not (is-member caller)) ERR-ALREADY-MEMBER)
    
    ;; Ensure token amount is valid (would likely require STX payment in a full implementation)
    (asserts! (> token-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Register member
    (map-set members caller {
      token-balance: token-amount,
      is-active: true,
      joined-at: block-height,
      delegated-to: none,
      is-expert: is-expert
    })
    
    ;; Update total tokens
    (var-set total-tokens-issued (+ (var-get total-tokens-issued) token-amount))
    
    (ok true)
  ))

;; Create a new proposal
(define-public (create-proposal (title (string-ascii 100)) 
                               (description (string-utf8 1000))
                               (link (string-ascii 255))
                               (funding-amount uint)
                               (milestones (list 10 {
                                 description: (string-utf8 200),
                                 amount: uint,
                                 completed: bool,
                                 funded: bool
                               })))
  (let (
    (caller tx-sender)
    (proposal-id (+ (var-get proposal-counter) u1))
    (phase-end-time (+ block-height (var-get submission-phase-length)))
  )
    ;; Ensure caller is a member
    (asserts! (is-member caller) ERR-NOT-MEMBER)
    
    ;; Verify total milestone amount matches funding amount
    (asserts! (is-eq funding-amount (fold + (map get-milestone-amount milestones) u0)) ERR-INVALID-AMOUNT)
    
    ;; Create the proposal
    (map-set proposals proposal-id {
      title: title,
      description: description,
      link: link,
      proposer: caller,
      created-at: block-height,
      funding-amount: funding-amount,
      state: PROPOSAL-STATE-DRAFT,
      current-phase: PHASE-SUBMISSION,
      phase-end-time: phase-end-time,
      yes-votes: u0,
      no-votes: u0,
      executed-at: none,
      milestones: milestones
    })
    
    ;; Increment proposal counter
    (var-set proposal-counter proposal-id)
    
    (ok proposal-id)
  ))

;; Helper function to get milestone amount (for use in fold)
(define-private (get-milestone-amount (milestone {
                                 description: (string-utf8 200),
                                 amount: uint,
                                 completed: bool,
                                 funded: bool
                               }))
  (get amount milestone))

;; Move proposal to discussion phase
(define-public (start-discussion-phase (proposal-id uint))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Ensure caller is the proposer
    (asserts! (is-eq caller (get proposer proposal)) ERR-NOT-AUTHORIZED)
    
    ;; Ensure proposal is in draft state and submission phase
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-DRAFT) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (is-eq (get current-phase proposal) PHASE-SUBMISSION) ERR-INVALID-PHASE)
    
    ;; Ensure submission phase has ended
    (asserts! (>= block-height (get phase-end-time proposal)) ERR-INVALID-PHASE)
    
    ;; Advance to discussion phase
    (advance-proposal-phase proposal-id PHASE-DISCUSSION (var-get discussion-phase-length))
  ))

;; Move proposal to voting phase
(define-public (start-voting-phase (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Ensure caller is the proposer or a member
    (asserts! (or 
                (is-eq tx-sender (get proposer proposal))
                (is-member tx-sender)) 
            ERR-NOT-AUTHORIZED)
    
    ;; Ensure proposal is in draft state and discussion phase
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-DRAFT) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (is-eq (get current-phase proposal) PHASE-DISCUSSION) ERR-INVALID-PHASE)
    
    ;; Ensure discussion phase has ended
    (asserts! (>= block-height (get phase-end-time proposal)) ERR-INVALID-PHASE)
    
    ;; Update proposal state to active and advance to voting phase
    (map-set proposals proposal-id (merge proposal { state: PROPOSAL-STATE-ACTIVE }))
    (advance-proposal-phase proposal-id PHASE-VOTING (var-get voting-phase-length))
  ))

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (member-info (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
    (effective-voter (default-to caller (get delegated-to member-info)))
  )
    ;; Ensure proposal is active and in voting phase
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-ACTIVE) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (is-voting-active proposal-id) ERR-VOTING-CLOSED)
    
    ;; If vote delegated, ensure we're using delegated principal
    (asserts! (or (is-eq caller effective-voter) (is-member effective-voter)) ERR-DELEGATION-NOT-ALLOWED)
    
    ;; Ensure member hasn't already voted
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: caller })) ERR-ALREADY-VOTED)
    
    ;; Calculate quadratic voting weight
    (let (
      (token-balance (get token-balance member-info))
      (voting-weight (calculate-quadratic-weight token-balance))
      (updated-yes-votes (if vote-for 
                            (+ (get yes-votes proposal) voting-weight)
                            (get yes-votes proposal)))
      (updated-no-votes (if vote-for
                          (get no-votes proposal)
                          (+ (get no-votes proposal) voting-weight)))
    )
      ;; Record vote
      (map-set proposal-votes 
        { proposal-id: proposal-id, voter: caller }
        { 
          vote: vote-for, 
          weight: voting-weight,
          voted-at: block-height
        })
      
      ;; Update vote counts
      (map-set proposals proposal-id (merge proposal {
        yes-votes: updated-yes-votes,
        no-votes: updated-no-votes
      }))
      
      (ok true)
    )
  ))

;; Delegate voting power to another member
(define-public (delegate-votes (delegate principal))
  (let (
    (caller tx-sender)
    (member-info (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
  )
    ;; Ensure delegate is a member
    (asserts! (is-member delegate) ERR-NOT-MEMBER)
    
    ;; Ensure delegate is not the same as caller
    (asserts! (not (is-eq caller delegate)) ERR-DELEGATION-NOT-ALLOWED)
    
    ;; Update delegation
    (map-set members caller (merge member-info {
      delegated-to: (some delegate)
    }))
    
    (ok true)
  ))

;; Remove vote delegation
(define-public (remove-delegation)
  (let (
    (caller tx-sender)
    (member-info (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
  )
    ;; Update delegation
    (map-set members caller (merge member-info {
      delegated-to: none
    }))
    
    (ok true)
  ))

;; Finalize proposal after voting period
(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Ensure proposal is active and in voting phase
    (asserts! (is-eq (get state proposal) PROPOSAL-STATE-ACTIVE) ERR-INVALID-PROPOSAL-STATE)
    (asserts! (is-eq (get current-phase proposal) PHASE-VOTING) ERR-INVALID-PHASE)
    
    ;; Ensure voting phase has ended
    (asserts! (>= block-height (get phase-end-time proposal)) ERR-INVALID-PHASE)
    
    ;; Determine if proposal passed
    (let (
      (passed (has-proposal-passed proposal-id))
      (new-state (if passed PROPOSAL-STATE-PASSED PROPOSAL-STATE-REJECTED))
    )
      ;; Update proposal state
      (map-set proposals proposal-id (merge proposal {
        state: new-state,
        current-phase: (if passed PHASE-EXECUTION PHASE-VOTING)
      }))
      
      (ok passed)
    )
  ))



;; Add funds to treasury
(define-public (add-to-treasury (amount uint))
  (begin
    ;; Ensure amount is valid
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update treasury balance
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    
    (ok true)
  ))

;; Cancel a proposal (only by proposer or if not yet in voting phase)
(define-public (cancel-proposal (proposal-id uint))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Ensure caller is the proposer
    (asserts! (is-eq caller (get proposer proposal)) ERR-NOT-AUTHORIZED)
    
    ;; Ensure proposal can be cancelled (not executed or rejected)
    (asserts! (not (or 
                    (is-eq (get state proposal) PROPOSAL-STATE-EXECUTED)
                    (is-eq (get state proposal) PROPOSAL-STATE-REJECTED)))
            ERR-INVALID-PROPOSAL-STATE)
    
    ;; Update proposal state
    (map-set proposals proposal-id (merge proposal {
      state: PROPOSAL-STATE-CANCELLED
    }))
    
    (ok true)
  ))

;; Update member expert status (admin function)
(define-public (update-expert-status (member principal) (is-expert bool))
  (let (
    (member-info (unwrap! (map-get? members member) ERR-NOT-MEMBER))
  )
    ;; In a real implementation, add admin check here
    ;; For demo purposes, allowing any call
    
    ;; Update member status
    (map-set members member (merge member-info {
      is-expert: is-expert
    }))
    
    (ok true)
  ))