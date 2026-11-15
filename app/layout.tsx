import type {Metadata,Viewport} from 'next';import './globals.css';
export const metadata:Metadata={title:'CUME · Finanças em perspectiva',description:'Seu dinheiro com clareza. Sua casa com confiança.',icons:{icon:'/favicon.svg'}};
export const viewport:Viewport={width:'device-width',initialScale:1,viewportFit:'cover'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="pt-BR" suppressHydrationWarning><head><script dangerouslySetInnerHTML={{__html:`try{var t=localStorage.getItem("cume-theme");document.documentElement.dataset.theme=t==="dark"?"dark":"light"}catch{}`}}/></head><body>{children}</body></html>}
