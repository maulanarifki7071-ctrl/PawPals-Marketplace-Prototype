
import { useEffect, useState, type FormEvent } from 'react'

import {
  ArrowRight,
  RefreshCw,
  ShieldCheck,
} from 'lucide-react'

import {
  Link,
  useNavigate,
} from 'react-router-dom'

import { useAuth } from '../../context/AuthContext'

import type { ResendOtpResult } from '../../types/auth'

import {
  api,
  getErrorMessage,
} from '../../lib/api'

type PendingOtp = {
  challengeId: string
  phone: string
  expiresAt?: string
}

function readPendingOtp(): PendingOtp | null {
  try {
    const saved = sessionStorage.getItem(
      'pawpals_pending_otp'
    )

    if (!saved) return null

    const data = JSON.parse(saved) as PendingOtp

    if (!data.challengeId || !data.phone) {
      return null
    }

    return data
  } catch {
    return null
  }
}

export default function VerifyOtpPage() {
  const navigate = useNavigate()
  const { verifyOtp } = useAuth()

  const [pendingOtp, setPendingOtp] =
    useState<PendingOtp | null>(readPendingOtp)

  const [code, setCode] = useState('')
  const [now,setNow]=useState(()=>Date.now())
  useEffect(()=>{const timer=window.setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(timer)},[])
  const remaining=pendingOtp?.expiresAt?Math.max(0,Math.ceil((Date.parse(pendingOtp.expiresAt)-now)/1000)):null
  const [loading, setLoading] = useState(false)
  const [resending, setResending] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>
  ) {
    event.preventDefault()

    if (!pendingOtp) return

    setError('')
    setNotice('')

    if (!/^\d{6}$/.test(code)) {
      setError('Masukkan kode OTP 6 digit.')
      return
    }

    try {
      setLoading(true)

      await verifyOtp(pendingOtp.challengeId, code)

      sessionStorage.removeItem('pawpals_pending_otp')

      navigate('/akun', {
        replace: true,
      })
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  async function handleResend() {
    if (!pendingOtp) return

    setError('')
    setNotice('')

    try {
      setResending(true)

      const result = await api<ResendOtpResult>(
        '/auth/otp/resend',
        {
          method: 'POST',
          body: JSON.stringify({
            challenge_id: pendingOtp.challengeId,
          }),
        }
      )

      const updated = {
        ...pendingOtp,
        challengeId: result.challenge_id,
        expiresAt:result.expires_at,
      }

      setPendingOtp(updated)
      setCode('')

      sessionStorage.setItem(
        'pawpals_pending_otp',
        JSON.stringify(updated)
      )

      setNotice('Kode OTP baru berhasil diminta.')
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setResending(false)
    }
  }

  if (!pendingOtp) {
    return (
      <main className="mx-auto max-w-lg px-5 py-24 text-center">
        <h1 className="text-2xl font-black text-[#173D3B]">
          Sesi Verifikasi Tidak Ditemukan
        </h1>

        <p className="mt-4 text-slate-600">
          Tidak ada permintaan OTP yang tersimpan
          pada browser ini.
        </p>

        <Link
          to="/daftar"
          className="mt-6 inline-block rounded-xl bg-[#0F766E] px-6 py-3 font-bold text-white"
        >
          Kembali ke Registrasi
        </Link>
      </main>
    )
  }

  return (
    <main className="flex min-h-[75vh] items-center justify-center bg-[#F7F4EC] px-5 py-14">
      <div className="w-full max-w-md rounded-[32px] bg-white p-8 text-center shadow-[0_20px_65px_rgba(15,118,110,0.08)] sm:p-10">

        <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-3xl bg-[#DFF3E9] text-[#0F766E]">
          <ShieldCheck size={40} />
        </div>

        <h1 className="mt-7 text-3xl font-black text-[#173D3B]">
          Verifikasi Nomor HP
        </h1>

        <p className="mt-4 text-sm leading-7 text-slate-500">
          Masukkan kode OTP yang dikirimkan untuk nomor
        </p>

        <p className="mt-1 font-bold text-[#0F766E]">
          {pendingOtp.phone}
        </p>

        {error && (
          <div
            role="alert"
            className="mt-6 rounded-xl bg-red-50 p-4 text-sm text-red-700"
          >
            {error}
          </div>
        )}

        {notice && (
          <div
            role="status"
            className="mt-6 rounded-xl bg-[#E6F6F1] p-4 text-sm text-[#0F766E]"
          >
            {notice}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-8">
          <label
            htmlFor="otp-code"
            className="mb-3 block text-sm font-bold text-[#173D3B]"
          >
            Kode OTP
          </label>

          <div className="relative grid grid-cols-6 gap-2" role="group" aria-label="Kode verifikasi enam digit"><input id="otp-code" type="text" inputMode="numeric" autoComplete="one-time-code" maxLength={6} required value={code} onChange={e=>setCode(e.target.value.replace(/\D/g,'').slice(0,6))} className="absolute inset-0 z-10 w-full opacity-0 cursor-text"/>{Array.from({length:6},(_,i)=><span aria-hidden="true" key={i} className={'grid aspect-square place-items-center rounded-xl border text-xl font-bold '+(i===code.length?'border-teal-600 bg-teal-50':'border-slate-200 bg-white')}>{code[i]||'·'}</span>)}</div>
          {remaining!==null&&Number.isFinite(remaining)&&<p className="mt-3 text-xs text-slate-500">{remaining?`Kode berlaku ${Math.floor(remaining/60)}:${String(remaining%60).padStart(2,'0')}`:'Kode mencapai batas waktu. Coba kirim ulang.'}</p>}


          <button
            type="submit"
            disabled={loading||code.length!==6}
            className="mt-6 flex w-full items-center justify-center gap-2 rounded-2xl bg-[#0F766E] py-4 font-bold text-white disabled:opacity-60"
          >
            {loading
              ? 'Memverifikasi...'
              : 'Verifikasi Akun'}

            {!loading && <ArrowRight size={18} />}
          </button>
        </form>

        <button
          type="button"
          disabled={resending || loading}
          onClick={handleResend}
          className="mt-6 inline-flex items-center gap-2 text-sm font-bold text-[#0F766E] hover:underline disabled:opacity-50"
        >
          <RefreshCw size={16} />
          {resending
            ? 'Mengirim ulang...'
            : 'Kirim ulang OTP'}
        </button>

        <p className="mt-5 text-xs leading-6 text-slate-400">
          Kode OTP hanya berlaku sementara.
          Jangan membagikannya kepada orang lain.
        </p>
      </div>
    </main>
  )
}
