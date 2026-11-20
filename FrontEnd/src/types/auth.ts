
export type Account = {
  id: string
  phone_e164: string
  display_name: string
  status: string
  email?: string | null
  phone_verified_at?: string | null
  created_at?: string
  vendor_id?: string | null
  vendor_status?: string | null
}

export type RegisterResult = {
  account: Account
  challenge_id: string
  expires_at?: string
}

export type LoginResult = {
  account: Account
}

export type VerifyOtpResult = {
  purpose: string
  authenticated?: boolean
  account?: Account
}

export type ResendOtpResult = {
  challenge_id: string
  expires_at?: string
}
