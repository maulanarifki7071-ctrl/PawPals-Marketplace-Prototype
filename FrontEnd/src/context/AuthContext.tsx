
import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react'

import type { Account } from '../types/auth'
import { api } from '../lib/api'

type AuthContextType = {
  account: Account | null
  checkingSession: boolean

  login: (
    phone: string,
    password: string
  ) => Promise<void>

  verifyOtp: (
    challengeId: string,
    code: string
  ) => Promise<void>

  logout: () => Promise<void>
}

const AuthContext = createContext<
  AuthContextType | undefined
>(undefined)

export function AuthProvider({
  children,
}: {
  children: ReactNode
}) {
  const [account, setAccount] =
    useState<Account | null>(null)

  const [checkingSession, setCheckingSession] =
    useState(true)

  // Periksa session ketika aplikasi pertama dibuka
  useEffect(() => {
    let active = true

    api<Account>('/accounts/me')
      .then((data) => {
        if (active) setAccount(data)
      })
      .catch(() => {
        if (active) setAccount(null)
      })
      .finally(() => {
        if (active) setCheckingSession(false)
      })

    return () => {
      active = false
    }
  }, [])

  async function refreshAccount() {
    const currentAccount =
      await api<Account>('/accounts/me')

    setAccount(currentAccount)
  }

  async function login(
    phone: string,
    password: string
  ) {
    await api('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        phone_e164: phone,
        password,
      }),
    })

    await refreshAccount()
  }

  async function verifyOtp(
    challengeId: string,
    code: string
  ) {
    await api('/auth/otp/verify', {
      method: 'POST',
      body: JSON.stringify({
        challenge_id: challengeId,
        code,
      }),
    })

    // Verifikasi registrasi juga membuat session
    await refreshAccount()
  }

  async function logout() {
    await api<void>('/auth/logout', {
      method: 'POST',
    })

    setAccount(null)
  }

  return (
    <AuthContext.Provider
      value={{
        account,
        checkingSession,
        login,
        verifyOtp,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const context = useContext(AuthContext)

  if (!context) {
    throw new Error(
      'useAuth harus digunakan di dalam AuthProvider'
    )
  }

  return context
}
