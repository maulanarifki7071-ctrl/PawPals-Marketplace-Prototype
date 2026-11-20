
export type Service = {
  min_price?: string | number | null
  public_city?: string | null
  rating_avg?: number | string
  rating_count?: number | string
  vendor_type?: string
  id: string
  name: string
  description: string | null
  category_code: string
  delivery_mode: string
  public_display_name?: string | null
}

export type ServicePackage = {
  id: string
  name: string
  description?: string | null
  price_amount: string | number
  duration_minutes: number
  is_active?: boolean
}

export type ServiceDetail = Service & {
  pet_rules?: Record<string,unknown> | null
  packages?: ServicePackage[]
  public_business_location?: unknown
}

export function deliveryLabel(mode: string): string {
  switch (mode) {
    case 'AT_VENDOR':
      return 'Di lokasi mitra'

    case 'AT_CUSTOMER':
      return 'Di lokasi customer'

    default:
      return mode.replaceAll('_', ' ')
  }
}

export function formatRupiah(
  amount: string | number
): string {
  return new Intl.NumberFormat('id-ID', {
    style: 'currency',
    currency: 'IDR',
    maximumFractionDigits: 0,
  }).format(Number(amount))
}
