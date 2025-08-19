# Payouts

Missing Code Identified:
  1. No PayoutRequest model to track payout requests
  2. The request_payout action doesn't actually create any records
  3. The payouts action references non-existent @current_affiliate.payouts
  4. No admin interface to manage payout requests
  5. Placeholder view for payout history

  Proposed Solution:
  - Create a PayoutRequest model with proper status workflow (pending → approved → paid)
  - Implement full request_payout functionality that creates trackable requests
  - Add admin interface for approving/rejecting/processing payout requests
  - Create proper payout history view for affiliates
  - Associate commissions with payout requests for better tracking

  This solution would create a complete payout request workflow where affiliates can request payouts, admins can review and approve them, and both parties can track the status throughout the process.
