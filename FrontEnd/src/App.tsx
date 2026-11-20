import type { ReactNode } from 'react'
import ScrollToTop from './components/layout/ScrollToTop'

import {
  BrowserRouter,
  Link,
  Navigate,
  Route,
  Routes,
  useLocation,
} from 'react-router-dom'

import WorkspaceLayout from './components/layout/WorkspaceLayout'
import {ConversationList,ConversationPage} from './pages/customer/BookingChat'

import {
  AuthProvider,
  useAuth,
} from './context/AuthContext'

import VendorCalendar from './pages/vendor/VendorCalendar'
import ActivityPage from './pages/customer/ActivityPage'
import CatalogPage from './pages/customer/CatalogPage'
import HomePage from './pages/customer/HomePage'
import ServiceDetailPage from './pages/customer/ServiceDetailPage'
import LoginPage from './pages/customer/LoginPage'
import RegisterPage from './pages/customer/RegisterPage'
import VerifyOtpPage from './pages/customer/VerifyOtpPage'
import AccountPage from './pages/customer/AccountPage'

import PetsPage, { PetDetail, Addresses } from './pages/customer/PetsPage'
import { NewBooking, CheckoutPage, BookingList, BookingDetail, Cases, CaseDetail } from './pages/customer/BookingPages'
import VendorHome, { VendorLocations, VendorServices, VendorServiceDetail, PayoutAccounts, VendorFinance, PayoutDetail } from './pages/vendor/VendorPages'
import AdminPage from './pages/admin/AdminPage'

// Halaman yang membutuhkan session login
function ProtectedRoute({
  children,
}: {
  children: ReactNode
}) {
  const { account, checkingSession } = useAuth()
  const location=useLocation()

  if (checkingSession) {
    return (
      <div className="flex min-h-[60vh] items-center justify-center text-[#0F766E]">
        Memeriksa session...
      </div>
    )
  }

  if (!account) {
    return (
      <Navigate
        to="/login"
        state={{from:location.pathname+location.search}}
        replace
      />
    )
  }

  return children
}

// Halaman 404
function NotFound() {
  return (
    <main className="flex min-h-[60vh] flex-col items-center justify-center px-5 text-center">
      <h1 className="text-6xl font-black text-[#173D3B]">
        404
      </h1>

      <p className="mt-4 text-slate-600">
        Halaman yang Anda cari tidak ditemukan.
      </p>

      <Link
        to="/"
        className="mt-6 rounded-2xl bg-[#0F766E] px-6 py-3 font-bold text-white"
      >
        Kembali ke Homepage
      </Link>
    </main>
  )
}

function PublicFooter(){const {pathname}=useLocation();if(/^\/(admin|mitra|akun|hewan|alamat|pesan|pesanan|aktivitas|bantuan)(\/|$)/.test(pathname))return null;return <footer className="pp-footer"><div><strong>PawPals.</strong><p>Perawatan untuk sahabat berbulu.</p></div><nav aria-label="Navigasi footer"><Link to="/">Beranda</Link><Link to="/layanan">Layanan</Link><Link to="/bantuan">Bantuan</Link><Link to="/mitra">Bergabung sebagai mitra</Link></nav><small>© 2026 PawPals</small></footer>}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <ScrollToTop />
        <div className="app-shell">

          <WorkspaceLayout>

          <Routes>
            {/* Public routes */}
            <Route
              path="/"
              element={<HomePage />}
            />

            <Route path="/layanan" element={<CatalogPage/>}/>
            <Route
              path="/layanan/:id"
              element={<ServiceDetailPage />}
            />

            <Route
              path="/login"
              element={<LoginPage />}
            />

            <Route
              path="/daftar"
              element={<RegisterPage />}
            />

            <Route
              path="/verifikasi-otp"
              element={<VerifyOtpPage />}
            />

            {/* Protected customer routes */}
            <Route
              path="/akun"
              element={
                <ProtectedRoute>
                  <AccountPage />
                </ProtectedRoute>
              }
            />

            <Route path="/hewan" element={<ProtectedRoute><PetsPage /></ProtectedRoute>} />
            <Route path="/hewan/:id" element={<ProtectedRoute><PetDetail /></ProtectedRoute>} />
            <Route path="/pesan" element={<ProtectedRoute><ConversationList/></ProtectedRoute>} />
            <Route path="/pesan/:id" element={<ProtectedRoute><ConversationPage/></ProtectedRoute>} />
            <Route path="/alamat" element={<ProtectedRoute><Addresses /></ProtectedRoute>} />
            <Route path="/booking/:id" element={<ProtectedRoute><NewBooking /></ProtectedRoute>} />
            <Route path="/checkout/:id" element={<ProtectedRoute><CheckoutPage/></ProtectedRoute>}/>
            <Route path="/pesanan" element={<ProtectedRoute><BookingList /></ProtectedRoute>} />
            <Route path="/pesanan/:id" element={<ProtectedRoute><BookingDetail /></ProtectedRoute>} />
            <Route path="/bantuan" element={<ProtectedRoute><Cases /></ProtectedRoute>} />
            <Route path="/bantuan/:id" element={<ProtectedRoute><CaseDetail /></ProtectedRoute>} />
            <Route path="/aktivitas" element={<ProtectedRoute><ActivityPage/></ProtectedRoute>}/>
            <Route path="/mitra/aktivitas" element={<ProtectedRoute><ActivityPage vendor/></ProtectedRoute>}/>
            <Route path="/mitra/jadwal" element={<ProtectedRoute><VendorCalendar/></ProtectedRoute>}/>
            <Route path="/mitra/pesan" element={<ProtectedRoute><ConversationList vendor/></ProtectedRoute>} />
            <Route path="/mitra/pesan/:id" element={<ProtectedRoute><ConversationPage vendor/></ProtectedRoute>} />
            <Route path="/mitra" element={<ProtectedRoute><VendorHome /></ProtectedRoute>} />
            <Route path="/mitra/lokasi" element={<ProtectedRoute><VendorLocations /></ProtectedRoute>} />
            <Route path="/mitra/layanan" element={<ProtectedRoute><VendorServices /></ProtectedRoute>} />
            <Route path="/mitra/layanan/:id" element={<ProtectedRoute><VendorServiceDetail /></ProtectedRoute>} />
            <Route path="/mitra/rekening" element={<ProtectedRoute><PayoutAccounts /></ProtectedRoute>} />
            <Route path="/mitra/keuangan" element={<ProtectedRoute><VendorFinance /></ProtectedRoute>} />
            <Route path="/mitra/payout/:id" element={<ProtectedRoute><PayoutDetail /></ProtectedRoute>} />
            <Route path="/mitra/pesanan" element={<ProtectedRoute><BookingList vendor /></ProtectedRoute>} />
            <Route path="/mitra/pesanan/:id" element={<ProtectedRoute><BookingDetail vendor /></ProtectedRoute>} />
            <Route path="/admin/*" element={<ProtectedRoute><AdminPage /></ProtectedRoute>} />

            <Route
              path="*"
              element={<NotFound />}
            />
          </Routes>
          </WorkspaceLayout>

          <PublicFooter/> 

        </div>
      </AuthProvider>
    </BrowserRouter>
  )
}
