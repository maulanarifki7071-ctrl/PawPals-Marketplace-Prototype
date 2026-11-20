import { useEffect, useState } from 'react'
import { api, getErrorMessage } from '../../lib/api'
import { secondary } from './Tools'
export default function PrivateMedia({path, image=true}:{path:string;image?:boolean}) {
  const [url,setUrl]=useState(''),[error,setError]=useState(''),[revision,setRevision]=useState(0)
  useEffect(()=>{const c=new AbortController();let object='';api<{url:string}>(path,{signal:c.signal}).then(async r=>{
    const u=new URL(r.url);const target=u.origin==='http://127.0.0.1:9100'?'/local-media'+u.pathname+u.search:u.href
    if(!image){if(!c.signal.aborted)setUrl(target);return}
    const response=await fetch(target,{signal:c.signal,credentials:'omit'});if(!response.ok)throw new Error('Gambar tidak dapat dimuat.');const blob=await response.blob();if(!blob.type.startsWith('image/'))throw new Error('Format gambar tidak valid.');if(!c.signal.aborted){object=URL.createObjectURL(blob);setUrl(object)}
  }).catch(e=>{if(!c.signal.aborted)setError(getErrorMessage(e))});return()=>{c.abort();if(object)URL.revokeObjectURL(object)}},[path,image,revision])
  if(error)return <div className="text-sm text-red-700">{error} <button className={secondary} onClick={()=>{setError('');setUrl('');setRevision(x=>x+1)}}>Coba lagi</button></div>
  if(!url)return <p className="text-xs text-slate-500">Memuat lampiran privat…</p>
  return image?<a href={url} target="_blank" rel="noreferrer" aria-label="Perbesar gambar"><img src={url} alt="Lampiran percakapan" className="max-h-72 max-w-full rounded-xl object-contain"/></a>:<a className={secondary} href={url} target="_blank" rel="noreferrer">Buka dokumen privat</a>
}
