const hero = '/photos/hero.webp'

import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  ArrowRight,
  Eye,
  EyeOff,
  UserRoundPlus,
} from 'lucide-react'

import { api } from '../../lib/api'

// ========================================
// TYPES
// ========================================

type RegisterResult = {
  account: {
    id: string
    phone_e164: string
    display_name: string
    status: string
  }
  challenge_id: string
  expires_at?: string
}

// ========================================
// HELPER NORMALISASI NOMOR HP
// ========================================

function formatPhoneE164(value: string): string {
  const digits = value.replace(/\D/g, '')

  let localNumber = digits

  if (digits.startsWith('62')) {
    localNumber = digits.slice(2)
  } else if (digits.startsWith('0')) {
    localNumber = digits.slice(1)
  }

  if (!/^8\d{7,12}$/.test(localNumber)) {
    throw new Error(
      'Masukkan nomor handphone Indonesia yang valid.'
    )
  }

  return `+62${localNumber}`
}

// ========================================
// STYLING
// ========================================

const inputClass =
  'w-full rounded-2xl border border-slate-200 ' +
  'bg-white px-5 py-4 text-[#123C3A] ' +
  'placeholder:text-slate-400 ' +
  'outline-none transition ' +
  'focus:border-[#0F766E] ' +
  'focus:ring-2 focus:ring-[#0F766E]/10'

// ========================================
// REGISTER PAGE
// ========================================

export default function RegisterPage() {
  const navigate = useNavigate()

  // Form states
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] =
    useState('')

  // Password visibility states
  const [showPassword, setShowPassword] =
    useState(false)

  const [
    showConfirmPassword,
    setShowConfirmPassword,
  ] = useState(false)

  // Request states
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  // ========================================
  // HANDLE REGISTER
  // ========================================

  async function handleRegister(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault()
    setError('')

    if (loading) return

    // Validate name
    if (!name.trim()) {
      setError('Nama lengkap wajib diisi.')
      return
    }

    if (name.trim().length > 150) {
      setError('Nama lengkap terlalu panjang.')
      return
    }

    // Validate password
    if (password.length < 10) {
      setError('Password minimal 10 karakter.')
      return
    }

    if (password.length > 128) {
      setError('Password maksimal 128 karakter.')
      return
    }

    // Confirm password
    if (password !== confirmPassword) {
      setError(
        'Password dan konfirmasi password tidak sama.'
      )
      return
    }

    setLoading(true)

    try {
      // Normalize phone number
      const formattedPhone = formatPhoneE164(phone)

      // Register through backend API
      const result = await api<RegisterResult>(
        '/auth/register',
        {
          method: 'POST',
          body: JSON.stringify({
            display_name: name.trim(),
            phone_e164: formattedPhone,
            password,
          }),
        }
      )

      if (!result.challenge_id) {
        throw new Error(
          'Registrasi berhasil, tetapi kode verifikasi tidak tersedia.'
        )
      }

      // Store OTP challenge for verification page
      sessionStorage.setItem(
        'pawpals_pending_otp',
        JSON.stringify({
          challengeId: result.challenge_id,
          phone: formattedPhone,
          expiresAt: result.expires_at,
        })
      )

      // Navigate to OTP verification
      navigate('/verifikasi-otp', {
        replace: true,
      })
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : 'Registrasi gagal. Silakan coba kembali.'
      )
    } finally {
      setLoading(false)
    }
  }

  // ========================================
  // RENDER
  // ========================================

  return (
    <main className="auth-shell min-h-[75vh] bg-[#F7F5EF] px-4 py-8"><div className="auth-visual"><img src={hero} alt="Ilustrasi anjing dan kucing PawPals"/><h2>Selamat datang di keluarga PawPals.</h2><p>Mulai dengan akun Anda, lalu tambahkan profil hewan kesayangan.</p></div>
      <div className="w-full max-w-[580px]">

        {/* REGISTER CARD */}
        <div className="rounded-[24px] bg-white px-6 py-7 shadow-xl shadow-[#123C3A]/5 sm:px-9 sm:py-9">

          {/* HEADER */}
          <div className="mb-6 text-center">

            {/* ICON */}
            <div className="mx-auto mb-8 flex h-20 w-20 items-center justify-center rounded-3xl bg-[#DDF4EA] text-[#0F766E]">
              <UserRoundPlus size={36} />
            </div>

            {/* TITLE */}
            <h1 className="text-3xl font-extrabold tracking-tight text-[#123C3A] sm:text-4xl">
              Bergabung dengan PawPals
            </h1>

            {/* DESCRIPTION */}
            <p className="mx-auto mt-5 max-w-lg leading-8 text-slate-500">
              Buat akun Anda dan mulai temukan layanan
              terbaik untuk hewan kesayangan.
            </p>
          </div>

          {/* REGISTER FORM */}
          <form
            onSubmit={handleRegister}
            className="space-y-7"
          >

            {/* NAME */}
            <div className="space-y-2">
              <label
                htmlFor="register-name"
                className="block font-semibold text-[#123C3A]"
              >
                Nama Lengkap
              </label>

              <input
                id="register-name"
                type="text"
                value={name}
                onChange={(e) =>
                  setName(e.target.value)
                }
                placeholder="Nama Anda"
                autoComplete="name"
                maxLength={150}
                required
                className={inputClass}
              />
            </div>

            {/* PHONE */}
            <div className="space-y-2">
              <label
                htmlFor="register-phone"
                className="block font-semibold text-[#123C3A]"
              >
                Nomor Handphone
              </label>

              <input
                id="register-phone"
                type="tel"
                value={phone}
                onChange={(e) =>
                  setPhone(e.target.value)
                }
                placeholder="081234567890"
                autoComplete="tel"
                inputMode="tel"
                required
                className={inputClass}
              />
            </div>

            {/* PASSWORD */}
            <div className="space-y-2">
              <label
                htmlFor="register-password"
                className="block font-semibold text-[#123C3A]"
              >
                Password
              </label>

              <div className="relative w-full">

                <input
                  id="register-password"
                  type={
                    showPassword
                      ? 'text'
                      : 'password'
                  }
                  value={password}
                  onChange={(e) =>
                    setPassword(e.target.value)
                  }
                  placeholder="Minimal 10 karakter"
                  autoComplete="new-password"
                  minLength={10}
                  maxLength={128}
                  required
                  className={`${inputClass} pr-14`}
                />

                {/* SHOW / HIDE PASSWORD */}
                <button
                  type="button"
                  onClick={() =>
                    setShowPassword((prev) => !prev)
                  }
                  aria-label={
                    showPassword
                      ? 'Sembunyikan password'
                      : 'Tampilkan password'
                  }
                  aria-pressed={showPassword}
                  className="absolute right-5 top-1/2 z-10 flex -translate-y-1/2 items-center justify-center text-slate-400 transition hover:text-[#0F766E]"
                >
                  {showPassword ? (
                    <EyeOff size={21} />
                  ) : (
                    <Eye size={21} />
                  )}
                </button>

              </div>
            </div>

            {/* CONFIRM PASSWORD */}
            <div className="space-y-2">
              <label
                htmlFor="register-confirm"
                className="block font-semibold text-[#123C3A]"
              >
                Konfirmasi Password
              </label>

              <div className="relative w-full">

                <input
                  id="register-confirm"
                  type={
                    showConfirmPassword
                      ? 'text'
                      : 'password'
                  }
                  value={confirmPassword}
                  onChange={(e) =>
                    setConfirmPassword(e.target.value)
                  }
                  placeholder="Ulangi password"
                  autoComplete="new-password"
                  maxLength={128}
                  required
                  className={`${inputClass} pr-14`}
                />

                {/* SHOW / HIDE CONFIRM PASSWORD */}
                <button
                  type="button"
                  onClick={() =>
                    setShowConfirmPassword(
                      (prev) => !prev
                    )
                  }
                  aria-label={
                    showConfirmPassword
                      ? 'Sembunyikan konfirmasi password'
                      : 'Tampilkan konfirmasi password'
                  }
                  aria-pressed={showConfirmPassword}
                  className="absolute right-5 top-1/2 z-10 flex -translate-y-1/2 items-center justify-center text-slate-400 transition hover:text-[#0F766E]"
                >
                  {showConfirmPassword ? (
                    <EyeOff size={21} />
                  ) : (
                    <Eye size={21} />
                  )}
                </button>

              </div>
            </div>

            {/* ERROR MESSAGE */}
            {error && (
              <div
                role="alert"
                className="rounded-2xl border border-red-100 bg-red-50 px-5 py-4 text-sm text-red-600"
              >
                {error}
              </div>
            )}

            {/* SUBMIT BUTTON */}
            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-3 rounded-2xl bg-[#0F766E] px-6 py-5 font-semibold text-white transition hover:bg-[#115E59] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {loading
                ? 'Sedang mendaftar...'
                : 'Daftar Sekarang'}

              {!loading && (
                <ArrowRight size={21} />
              )}
            </button>

          </form>

          {/* LOGIN LINK */}
          <p className="mt-8 text-center text-sm text-slate-500">
            Sudah memiliki akun?{' '}

            <Link
              to="/login"
              className="font-bold text-[#0F766E] transition hover:underline"
            >
              Masuk sekarang
            </Link>
          </p>

        </div>
      </div>
    </main>
  )
}
