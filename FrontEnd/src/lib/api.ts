
export class ApiError extends Error {
  public readonly status: number
  public readonly code: string

  constructor(
    status: number,
    code: string,
    message: string
  ) {
    super(message)

    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}


type ApiErrorBody = {
  error?: {
    code?: string
    message?: string
  }
}

// Semua request menggunakan Vite proxy /api
export async function api<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const headers = new Headers(options.headers)

  if (options.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json')
  }

  const response = await fetch(`/api/v1${path}`, {
    ...options,
    headers,
    credentials: 'include',
  })

  if (!response.ok) {
    const body = (await response
      .json()
      .catch(() => null)) as ApiErrorBody | null

    throw new ApiError(
      response.status,
      body?.error?.code ?? 'HTTP_ERROR',
      body?.error?.message ??
        `Request gagal (${response.status})`
    )
  }

  if (response.status === 204) {
    return undefined as T
  }

  const result = (await response.json()) as {
    data: T
  }

  return result.data
}

// Mengubah 0812... menjadi +62812...
export function normalizePhone(value: string): string {
  const phone = value.replace(/[\s()-]/g, '')

  if (phone.startsWith('0')) {
    return `+62${phone.slice(1)}`
  }

  if (phone.startsWith('62')) {
    return `+${phone}`
  }

  return phone
}

// Menampilkan pesan error yang mudah dimengerti
export function getErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    const messages: Record<string, string> = {
      SERVICE_NOT_BOOKABLE:'Layanan atau paket belum dapat dipesan.',
      INVALID_STATE_TRANSITION:'Tindakan tidak tersedia pada status saat ini.',
      OUTSIDE_SERVICE_AREA:'Alamat di luar jangkauan layanan mitra.',
      CUSTOMER_ADDRESS_REQUIRED:'Pilih alamat layanan terlebih dahulu.',
      AVAILABILITY_OVERLAP:'Jadwal bertabrakan dengan jadwal yang sudah ada.',
      CAPACITY_OVERRIDE_OVERLAP:'Pengaturan kapasitas bertabrakan dengan interval yang sudah ada.',
      ADMIN_PERMISSION_REQUIRED:'Akun tidak memiliki akses administrasi.',
      SLOT_UNAVAILABLE:'Jadwal tidak tersedia lagi. Pilih jadwal lain.',
      PET_NOT_COMPATIBLE:'Hewan tidak sesuai dengan ketentuan layanan.',
      MINIMUM_NOTICE_NOT_MET:'Waktu pemesanan terlalu dekat dengan jadwal layanan.',
      MEDIA_STORAGE_UNAVAILABLE:'Penyimpanan gambar tidak dapat dihubungi. Coba lagi.',
      CONCURRENT_UPDATE:'Data berubah saat diproses. Silakan coba lagi.',
      INTERNAL_SERVER_ERROR:'Terjadi kendala pada sistem. Coba lagi atau hubungi bantuan.',
      INVALID_CREDENTIALS:
        'Nomor HP atau password tidak sesuai.',

      PHONE_ALREADY_REGISTERED:
        'Nomor HP ini sudah terdaftar.',

      PHONE_VERIFICATION_REQUIRED:
        'Akun belum diverifikasi. Selesaikan verifikasi OTP.',

      ACCOUNT_DISABLED:
        'Akun ini sedang dinonaktifkan.',

      OTP_INVALID:
        'Kode OTP tidak sesuai.',

      OTP_EXPIRED:
        'Kode OTP sudah kedaluwarsa.',

      OTP_LOCKED:
        'Percobaan OTP telah mencapai batas.',

      OTP_ALREADY_USED:
        'Kode OTP sudah digunakan.',

      OTP_RESEND_TOO_SOON:
        'Tunggu beberapa saat sebelum meminta OTP baru.',

      RATE_LIMITED:
        'Terlalu banyak percobaan. Coba lagi nanti.',

      OTP_DELIVERY_UNAVAILABLE:
        'Layanan pengiriman OTP belum tersedia.',

      AUTHENTICATION_REQUIRED:
        'Silakan login terlebih dahulu.',

      AUTH_REQUIRED:
        'Silakan login terlebih dahulu.',
    }

    return messages[error.code] ?? error.message
  }

  if (error instanceof Error) {
    return error.message
  }

  return 'Terjadi kesalahan. Silakan coba lagi.'
}
