import {servicePhoto,categoryLabel} from '../../components/services/photo'



import {
  ArrowLeft,
  Clock3,
  MapPin,
} from 'lucide-react'

import {
  Link,
  useParams,
} from 'react-router-dom'

import { Collection, Details, useData } from '../../components/workspace/Tools'

import type {
  ServiceDetail,
} from '../../types/Service'

import {
  deliveryLabel,
  formatRupiah,
} from '../../types/Service'

export default function ServiceDetailPage() {
  const { id } = useParams<{ id: string }>()

  const {data: service, loading, error: loadError} = useData<ServiceDetail>(id ? `/services/${encodeURIComponent(id)}` : null)
  const error = id ? loadError : 'ID layanan tidak ditemukan'


  return (
    <main className="detail-premium">

      <div className="home-container">

        <Link
          to="/layanan"
          className="inline-flex items-center gap-2 text-sm font-semibold text-[#0F766E] hover:underline"
        >
          <ArrowLeft size={17} />
          Kembali ke katalog
        </Link>

        {loading && (
          <p className="mt-10 text-slate-500">
            Memuat detail layanan...
          </p>
        )}

        {error && (
          <p className="mt-10 rounded-2xl bg-red-50 p-5 text-red-700">
            {error}
          </p>
        )}

        {!loading && !error && service && (
          <div className="detail-layout">

            {/* Header layanan */}
            <div className="detail-gallery">

              <img src={servicePhoto(service)} alt="Ilustrasi layanan"/><p className="photo-note">Ilustrasi kategori, bukan foto fasilitas mitra.</p><span className="category-label">
                {categoryLabel(service.category_code)}
              </span>

              <h1 className="detail-title">
                {service.name}
              </h1>

              {service.public_display_name && (
                <p className="mt-3 font-semibold text-[#0F766E]">
                  {service.public_display_name}
                </p>
              )}
            </div>

            <div className="detail-content">

              <h2 className="text-xl font-extrabold text-[#173D3B]">
                Tentang layanan
              </h2>

              <p className="mt-4 leading-8 text-slate-600">
                {service.description ||
                  'Informasi layanan belum tersedia.'}
              </p>

              <p className="mt-5 inline-flex items-center gap-2 text-sm font-medium text-slate-600">
                <MapPin
                  size={17}
                  className="text-[#0F766E]"
                />
                {deliveryLabel(service.delivery_mode)}
              </p>

              {service.pet_rules&&<div className="mt-6 rounded-2xl border border-[#DFEAE5] p-5"><h2 className="font-bold mb-3">Ketentuan penerimaan hewan</h2><Details row={service.pet_rules} keys={['accepted_species','accepted_size_codes','accepts_reactive','accepts_aggressive_history','context_notes']}/></div>}
              <h2 className="mt-10 text-xl font-extrabold text-[#173D3B]">
                Pilihan paket
              </h2>

              {service.packages?.length ? (
                <div className="mt-5 grid gap-4 sm:grid-cols-2">

                  {service.packages.map((pkg) => (
                    <div
                      key={pkg.id}
                      className="rounded-2xl border border-[#DFEAE5] p-5"
                    >
                      <h3 className="font-bold text-[#173D3B]">
                        {pkg.name}
                      </h3>

                      {pkg.description && (
                        <p className="mt-2 text-sm leading-6 text-slate-600">
                          {pkg.description}
                        </p>
                      )}

                      <div className="mt-4 flex flex-wrap items-center justify-between gap-2">

                        <span className="text-lg font-black text-[#0F766E]">
                          {formatRupiah(pkg.price_amount)}
                        </span>

                        <span className="inline-flex items-center gap-1 text-xs text-slate-500">
                          <Clock3 size={15} />
                          {pkg.duration_minutes} menit
                        </span>
                      </div>
                      <Link to={`/booking/${service.id}?paket=${pkg.id}`} className="mt-4 block rounded-xl bg-[#0F766E] px-4 py-3 text-center text-sm font-bold text-white hover:bg-[#115E59]">Pilih paket</Link>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="mt-4 text-sm text-slate-500">
                  Belum ada paket yang ditampilkan melalui API.
                </p>
              )}

              <div className="mt-8 rounded-2xl bg-[#EDF7F1] p-4 text-sm leading-6 text-[#315D56]">
                Pilih paket untuk menentukan hewan dan jadwal reservasi. Kapasitas dikonfirmasi oleh sistem saat booking dibuat.
              </div>
              <h2 className="mt-10 mb-4 text-xl font-extrabold">Ulasan pelanggan</h2>
              <Collection path={`/services/${service.id}/reviews`}>{r=><Details row={r} keys={['reviewer_name','rating','comment','created_at']}/>}</Collection>
            </div>
          </div>
        )}
      </div>
    </main>
  )
}
