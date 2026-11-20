const hero = '/photos/hero.webp'

import { useState, type FormEvent } from 'react'

import {
  ArrowRight,
  LockKeyhole,
  PawPrint,
  Phone,
  Eye,
  EyeOff,
} from 'lucide-react'

import {
  Link,
  useNavigate,
  useLocation,
} from 'react-router-dom'

import { useAuth } from '../../context/AuthContext'

import {
  getErrorMessage,
  normalizePhone,
} from '../../lib/api'

export default function LoginPage() {
  const navigate = useNavigate()
  const location=useLocation()
  const { login } = useAuth()

  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault()
    setError('')

    const formattedPhone = normalizePhone(phone)

    if (!/^\+62\d{8,13}$/.test(formattedPhone)) {
      setError('Masukkan nomor HP Indonesia yang valid.')
      return
    }

    try {
      setLoading(true)

      await login(formattedPhone, password)

      const from=location.state?.from
      navigate(typeof from==='string'&&from.startsWith('/')&&!from.startsWith('//')?from:'/akun', { replace: true })
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <main className="auth-shell min-h-[75vh] bg-[#F7F4EC] px-5 py-10"><div className="auth-visual"><img src={hero} alt="Ilustrasi anjing dan kucing PawPals"/><h2>Perawatan terbaik, setiap hari.</h2><p>Atur jadwal, temukan mitra, dan pantau sahabat berbulu dalam satu tempat.</p></div>
      <div className="w-full max-w-md rounded-[24px] bg-white p-7 shadow-[0_20px_65px_rgba(15,118,110,0.08)] sm:p-10">

        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-[#DFF3E9] text-[#0F766E]">
          <PawPrint size={34} />
        </div>

        <h1 className="mt-6 text-center text-3xl font-black text-[#173D3B]">
          Selamat Datang!
        </h1>

        <p className="mt-3 text-center text-sm leading-7 text-slate-500">
          Masuk ke PawPals untuk mengelola
          kebutuhan sahabat berbulu Anda.
        </p>

        {error && (
          <div
            role="alert"
            className="mt-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700"
          >
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-8 space-y-5">

          <div>
            <label
              htmlFor="login-phone"
              className="mb-2 block text-sm font-bold text-[#173D3B]"
            >
              Nomor Handphone
            </label>

            <div className="flex items-center gap-3 rounded-2xl border border-slate-200 px-4 focus-within:border-[#0F766E]">
              <Phone size={19} className="text-[#0F766E]" />

              <input
                id="login-phone"
                type="tel"
                autoComplete="tel"
                required
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="081234567890"
                className="w-full py-4 text-sm outline-none"
              />
            </div>
          </div>

          <div className="space-y-2">
            <label
              htmlFor="login-password"
              className="block font-semibold text-[#123C3A]"
            >
              Password
            </label>

            <div className="relative w-full">
              <LockKeyhole
                size={20}
                className="pointer-events-none absolute left-5 top-1/2 -translate-y-1/2 text-[#0F766E]"
              />

              <input
                id="login-password"
                type={showPassword ? "text" : "password"}
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Masukkan password"
                className="w-full rounded-2xl border border-slate-200 bg-white py-4 pl-14 pr-14 outline-none transition focus:border-[#0F766E]"
              />

              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                aria-label={
                    showPassword ? "Sembunyikan password" : "Tampilkan password"}
                aria-pressed={showPassword}
                className="absolute right-5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-[#0F766E]"
             >
                {showPassword ? ( 
                    <EyeOff size={21} /> 
                ) : ( 
                    <Eye size={21} />
                )}
             </button>
            </div>
          </div>

        <button
            type="submit"
            disabled={loading}
            className="flex w-full items-center justify-center gap-3 rounded-2xl bg-[#0F766E] px-6 py-4 font-semibold text-white transition hover:bg-[#115E59] disabled:opacity-60"
        >
            {loading ? 'Sedang masuk...' : 'Masuk'}
            {!loading && <ArrowRight size={18} />}
            </button>  
        </form>

        <p className="mt-7 text-center text-sm text-slate-500">
          Belum memiliki akun?{' '}
          <Link
            to="/daftar"
            className="font-bold text-[#0F766E] hover:underline"
          >
            Daftar sekarang
          </Link>
        </p>
      </div>
    </main>
  )
}
