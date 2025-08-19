module PaymentsHelper
  def payment_status_class(status)
    case status
    when "pending"
      "inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-yellow-100 text-yellow-800"
    when "paid", "overpaid"
      "inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800"
    when "partial"
      "inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-blue-100 text-blue-800"
    when "expired", "failed"
      "inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-red-100 text-red-800"
    else
      "inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-gray-100 text-gray-800"
    end
  end
end
