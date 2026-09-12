(() => {
  const adminMode = document.body.dataset.mode === 'admin';
  const layer = document.getElementById('layer');
  const app = document.getElementById('app');
  const clientSearchKey = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
  const clientIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/></svg>';
  const searchIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.4-4.4"/></svg>';
  const usernameDomain = '@floralis.local';
  const principalLoginEmail = 'admin@floralis.local';
  const pdvProfilesKey = 'floralis.pdv.profiles.v1';

  function readPdvProfiles() {
    try {
      const profiles = JSON.parse(localStorage.getItem(pdvProfilesKey) || '[]');
      return Array.isArray(profiles) ? profiles.filter(profile => profile?.email && profile?.name).slice(0, 6) : [];
    } catch {
      return [];
    }
  }

  function rememberPdvProfile(session) {
    if (document.body.dataset.mode !== 'standalone-pos' || !session?.email || !session?.name) return;
    const profiles = readPdvProfiles().filter(profile => profile.userId !== session.userId && profile.email !== session.email);
    profiles.unshift({userId: session.userId || session.email, name: session.name, email: session.email, role: session.role || 'employee'});
    localStorage.setItem(pdvProfilesKey, JSON.stringify(profiles.slice(0, 6)));
  }

  if (document.body.dataset.mode === 'standalone-pos') {
    try { rememberPdvProfile(JSON.parse(localStorage.getItem('floralis.session.v1') || 'null')); } catch {}
  }

  if (window.FLORALIS_CONFIG?.mode === 'supabase' && window.FloralisBackend?.login && !window.FloralisBackend.login.__acceptsUsername) {
    const remoteLogin = window.FloralisBackend.login.bind(window.FloralisBackend);
    const loginWithUsername = (identifier, password) => {
      const normalized = String(identifier || '').trim().toLowerCase();
      const isPrincipal = normalized === 'marcos' || normalized === `marcos${usernameDomain}`;
      const email = isPrincipal ? principalLoginEmail : normalized.includes('@') ? normalized : `${normalized}${usernameDomain}`;
      return remoteLogin(email, password).then(session => {
        rememberPdvProfile(session);
        return session;
      });
    };
    loginWithUsername.__acceptsUsername = true;
    window.FloralisBackend.login = loginWithUsername;
  }

  const clientStyles = document.createElement('style');
  clientStyles.textContent = `
    .pos-client-strip{min-height:66px;margin:10px 32px 12px;padding:9px 10px 9px 13px;border:1px solid var(--line);border-radius:15px;background:var(--surface-2);display:flex;align-items:center;gap:9px}.pos-client-strip.selected{border-color:color-mix(in srgb,var(--accent) 40%,var(--line));background:color-mix(in srgb,var(--accent-soft) 65%,var(--surface))}.pos-client-strip-icon{width:39px;height:39px;border-radius:12px;background:var(--surface);color:var(--accent);display:grid;place-items:center;flex:none;box-shadow:0 4px 12px rgba(24,39,75,.06)}.pos-client-strip-icon svg{width:18px;fill:none;stroke:currentColor;stroke-width:2}.pos-client-strip-copy{min-width:140px;flex:1}.pos-client-strip-copy>*{display:block}.pos-client-strip-copy small{font-size:7px;letter-spacing:.08em;color:var(--muted);font-weight:800}.pos-client-strip-copy strong{margin:2px 0;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pos-client-strip-copy span{font-size:8px;color:var(--muted)}.pos-client-strip button{height:38px;min-width:auto;padding:0 12px;white-space:nowrap}.pos-client-strip button[data-pdv-client-new]{font-size:9px}
    .pos-client-picker-head>b{height:29px;padding:0 10px;border-radius:9px;background:var(--surface);color:var(--muted);font-size:9px;display:flex;align-items:center;white-space:nowrap}.pos-client-search-field{position:sticky;top:0;z-index:2;padding:4px 0 10px;background:var(--surface)}.pos-client-search-box{height:48px;border:2px solid color-mix(in srgb,var(--accent) 55%,var(--line));border-radius:13px;background:var(--surface);display:flex;align-items:center;gap:9px;padding:0 13px;box-shadow:0 5px 18px rgba(24,39,75,.06)}.pos-client-search-box:focus-within{border-color:var(--accent);box-shadow:0 0 0 4px var(--accent-soft)}.pos-client-search-box svg{width:18px;fill:none;stroke:var(--accent);stroke-width:2}.pos-client-search-box input{height:42px!important;padding:0!important;border:0!important;box-shadow:none!important;font-size:12px!important;flex:1}.pos-consumer-final{width:100%;min-height:60px;margin:0 0 10px;padding:9px 12px;border:1px solid var(--line);border-radius:13px;background:var(--surface);display:flex;align-items:center;gap:10px;text-align:left;cursor:pointer}.pos-consumer-final:hover,.pos-consumer-final.selected{border-color:var(--accent);background:var(--accent-soft)}.pos-consumer-final>span{width:35px;height:35px;border-radius:10px;background:var(--surface-2);color:var(--accent);display:grid;place-items:center}.pos-consumer-final svg{width:16px;fill:none;stroke:currentColor;stroke-width:2}.pos-consumer-final>div{min-width:0;flex:1}.pos-consumer-final strong,.pos-consumer-final small{display:block}.pos-consumer-final strong{font-size:11px}.pos-consumer-final small{margin-top:3px;color:var(--muted);font-size:8px}.pos-consumer-final>b{color:var(--accent);font-size:9px}.pos-client-results{max-height:48vh;overflow:auto;border:1px solid var(--line);border-radius:13px}.pos-client-table tr.selected td{background:var(--accent-soft)}
    @media(max-width:900px){.pos-client-strip{margin-inline:16px}.pos-client-strip button[data-pdv-client-clear]{display:none}}
    @media(max-width:720px){.pos-client-strip{min-height:62px;margin:7px 9px;padding:7px 8px;border-radius:14px;gap:7px}.pos-client-strip-icon{width:36px;height:36px}.pos-client-strip-copy{min-width:0}.pos-client-strip-copy span{display:none}.pos-client-strip button{height:36px;padding:0 9px;font-size:8px}.pos-client-strip button[data-pdv-client-new]{width:36px;padding:0;font-size:0}.pos-client-strip button[data-pdv-client-new]::after{content:'+';font-size:18px}.pos-catalog,.pos-cart-panel{height:calc(100dvh - 408px)}.pos-client-results{max-height:43vh}}
    @media(max-width:420px){.pos-client-strip-copy small{font-size:6px}.pos-client-strip-copy strong{font-size:10px}.pos-consumer-final small{display:none}}

    /* Entrada do PDV por perfis locais. Guarda somente o identificador, nunca a senha. */
    .pdv-profile-login{margin:2px 0 18px;display:grid;gap:13px}.pdv-profile-heading strong,.pdv-profile-heading small{display:block}.pdv-profile-heading strong{font-size:17px;line-height:1.2}.pdv-profile-heading small{margin-top:5px;color:var(--muted);font-size:11px;line-height:1.45}.pdv-profile-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px}.pdv-profile-card{min-width:0;min-height:116px;padding:10px 7px;border:1px solid var(--line);border-radius:12px;background:var(--surface);color:var(--text);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;cursor:pointer;box-shadow:none}.pdv-profile-card>span{width:49px;height:49px;border-radius:15px;background:linear-gradient(145deg,var(--accent),#94040a);color:#fff;display:grid;place-items:center;font-size:21px;font-weight:900}.pdv-profile-card>strong{max-width:100%;font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pdv-profile-card>small{color:var(--muted);font-size:8px}.pdv-profile-card:hover,.pdv-profile-card.active{border-color:var(--accent);background:var(--accent-soft);box-shadow:0 0 0 3px rgba(var(--accent-rgb),.12)}.pdv-profile-other>span{background:var(--surface-2);border:1px dashed var(--line);color:var(--muted);font-size:27px;font-weight:450}.pdv-profile-other.active>span{border-color:var(--accent);color:var(--accent)}
    @media(max-width:520px){.pdv-profile-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.pdv-profile-card{min-height:105px}.pdv-profile-card>span{width:44px;height:44px}}

    /* Escala Grande: tipografia, campos, tabelas e alvos de toque crescem juntos. */
    html[data-scale="large"]{font-size:18px}
    html[data-scale="large"] .page-title,html[data-scale="large"] .page-title h1{font-size:36px!important;line-height:1.08}
    html[data-scale="large"] .page-count,html[data-scale="large"] .section-heading p,html[data-scale="large"] .login-copy{font-size:15px!important;line-height:1.55}
    html[data-scale="large"] .btn,html[data-scale="large"] .filter,html[data-scale="large"] select,html[data-scale="large"] input:not([type="radio"]):not([type="checkbox"]),html[data-scale="large"] textarea{min-height:54px;font-size:16px!important}
    html[data-scale="large"] .btn.small{min-height:46px;font-size:14px!important}
    html[data-scale="large"] .menu-item,html[data-scale="large"] .tab,html[data-scale="large"] .settings-nav button,html[data-scale="large"] .tabs button,html[data-scale="large"] .subnav button{min-height:52px;font-size:15px!important}
    html[data-scale="large"] .menu-label{font-size:14px!important}
    html[data-scale="large"] .metric{min-height:142px;padding:22px}
    html[data-scale="large"] .metric span,html[data-scale="large"] .metric small{font-size:14px!important}
    html[data-scale="large"] .metric strong{font-size:32px!important}
    html[data-scale="large"] .data-table th{height:54px;font-size:13px!important}
    html[data-scale="large"] .data-table td{height:62px;font-size:15px!important}
    html[data-scale="large"] .data-table td strong{font-size:16px!important}
    html[data-scale="large"] .shell-choice strong,html[data-scale="large"] .interface-scale-option strong,html[data-scale="large"] .choice-card strong,html[data-scale="large"] .font-choice-option strong{font-size:16px!important}
    html[data-scale="large"] .shell-choice small,html[data-scale="large"] .interface-scale-option small,html[data-scale="large"] .choice-label,html[data-scale="large"] .scale-hint,html[data-scale="large"] .font-choice-option small{font-size:13px!important}
    html[data-scale="large"] .pdv-title h1{font-size:34px!important}
    html[data-scale="large"] .pdv-title .terminal-label,html[data-scale="large"] .shortcut-trigger,html[data-scale="large"] .sync-pill{font-size:13px!important}
    html[data-scale="large"] .pdv-search .search-field input{height:60px!important;font-size:18px!important}
    html[data-scale="large"] .quantity-field{font-size:14px!important}
    html[data-scale="large"] .quantity-field input{width:104px;min-height:60px;font-size:18px!important}
    html[data-scale="large"] .pos-product-card strong{font-size:16px!important}
    html[data-scale="large"] .pos-product-card small{font-size:13px!important}
    html[data-scale="large"] .pos-product-card b{font-size:20px!important}
    html[data-scale="large"] .pos-cart-panel header strong,html[data-scale="large"] .pos-cart-panel header b{font-size:16px!important}
    html[data-scale="large"] .pos-cart-panel td{font-size:15px!important}
    html[data-scale="large"] .pdv-total span{font-size:14px!important}
    html[data-scale="large"] .pdv-total strong{font-size:36px!important}
    html[data-scale="large"] .pos-touch-shortcuts button{min-height:104px;padding:14px 10px}
    html[data-scale="large"] .pos-touch-shortcuts button span{font-size:15px!important}
    html[data-scale="large"] .pos-touch-shortcuts kbd{font-size:13px!important}
    html[data-scale="large"] .pos-client-strip{min-height:82px}
    html[data-scale="large"] .pos-client-strip-copy small{font-size:11px}
    html[data-scale="large"] .pos-client-strip-copy strong{font-size:17px}
    html[data-scale="large"] .pos-client-strip-copy span{font-size:13px}
    html[data-scale="large"] .layer-card h2{font-size:30px!important}
    html[data-scale="large"] .login-card{max-width:520px;padding:42px}
    html[data-scale="large"] .login-card h2{font-size:34px!important}
    html[data-scale="large"] .login-card label{font-size:14px!important}

    /* Minimum: visual FLORALIS escuro, amplo e sem ornamentos desnecessários. */
    html[data-shell="minimum"]{--surface:#292a2d;--surface-2:#202124;--panel:#2e2f32;--line:#4a4b50;--text:#f7f7f8;--muted:#b7b8bd;--accent:#652276;--accent-rgb:101,34,118;--accent-soft:rgba(101,34,118,.15);color-scheme:dark}
    html[data-shell="minimum"] body,html[data-shell="minimum"] #app{background:#202124;color:var(--text)}
    html[data-shell="minimum"] .nex-shell,html[data-shell="minimum"] .nex-workspace,html[data-shell="minimum"] .app-shell,html[data-shell="minimum"] .main,html[data-shell="minimum"] .page{background:#202124}
    html[data-shell="minimum"] .nex-navbar,html[data-shell="minimum"] .sidebar{background:#191a1c;border-color:#3d3e42;box-shadow:none}
    html[data-shell="minimum"] .menu-item,html[data-shell="minimum"] .sidebar .nav-item{border-radius:9px;color:#c9c9cd;box-shadow:none}
    html[data-shell="minimum"] .menu-item.active,html[data-shell="minimum"] .nex-navbar.open .menu-item.active,html[data-shell="minimum"] .sidebar .nav-item.active{background:var(--accent);border-left:0;color:#fff;box-shadow:none}
    html[data-shell="minimum"] .menu-item:hover{background:#303135}
    html[data-shell="minimum"] .page-header,html[data-shell="minimum"] .topbar,html[data-shell="minimum"] .page-head{background:#202124;border-color:var(--line);box-shadow:none}
    html[data-shell="minimum"] .panel,html[data-shell="minimum"] .metric,html[data-shell="minimum"] .card,html[data-shell="minimum"] .data-region,html[data-shell="minimum"] .settings-nav,html[data-shell="minimum"] .settings-content{background:var(--surface);border-color:var(--line);border-radius:12px;box-shadow:none}
    html[data-shell="minimum"] .btn,html[data-shell="minimum"] input,html[data-shell="minimum"] select,html[data-shell="minimum"] textarea,html[data-shell="minimum"] .filter{border-radius:8px;box-shadow:none}
    html[data-shell="minimum"] input,html[data-shell="minimum"] select,html[data-shell="minimum"] textarea,html[data-shell="minimum"] .field input,html[data-shell="minimum"] .field select,html[data-shell="minimum"] .field textarea{background:#202124;border-color:#55565b;color:#f7f7f8}
    html[data-shell="minimum"] .layer-card,html[data-shell="minimum"] .layer-head,html[data-shell="minimum"] .layer-body,html[data-shell="minimum"] .layer-foot,html[data-shell="minimum"] .suggestions,html[data-shell="minimum"] .suggestion,html[data-shell="minimum"] .payment-option{background:#292a2d;border-color:#4a4b50;color:#f7f7f8}
    html[data-shell="minimum"] .btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
    html[data-shell="minimum"] .btn.secondary,html[data-shell="minimum"] .btn:not(.primary){background:#303135;border-color:#55565b;color:var(--text)}
    html[data-shell="minimum"] .data-table thead,html[data-shell="minimum"] .data-table th{background:#242528;color:#d7d7da}
    html[data-shell="minimum"] .data-table td{border-color:#414247}
    html[data-shell="minimum"] .metric::before,html[data-shell="minimum"] .metric::after{display:none!important}
    html[data-shell="minimum"] .login-page{background:#202124}
    html[data-shell="minimum"] .login-visual{background:#191a1c;color:#fff}
    html[data-shell="minimum"] .login-panel,html[data-shell="minimum"] .login-card{background:#292a2d;color:#fff}
    html[data-shell="minimum"] .login-card{border:1px solid var(--line);border-radius:14px;box-shadow:none}
    .shell-preview-minimum{background:#202124;border-color:#48494e;border-radius:8px}
    .shell-preview-minimum i{inset:0 auto 0 0;width:18%;background:#191a1c;border-right:1px solid #47484c}
    .shell-preview-minimum b{left:24%;right:7%;top:11%;height:20%;border-radius:4px;background:#292a2d}
    .shell-preview-minimum em{left:24%;right:7%;top:39%;bottom:10%;border-radius:5px;background:linear-gradient(90deg,#652276 0 26%,#292a2d 26%)}

    .pos-theme-preview.theme-minimum{background:#202124;border-color:#4a4b50;border-radius:8px}
    .pos-theme-preview.theme-minimum span,.pos-theme-preview.theme-minimum i,.pos-theme-preview.theme-minimum b{border-color:#4a4b50;border-radius:5px;background:#2b2c2f}
    .pos-theme-preview.theme-minimum i{outline:2px solid #652276;outline-offset:-2px}
    .pos-theme-preview.theme-minimum small{color:#f5f5f6}
    .pdv.pos-theme-minimum{--surface:#292a2d;--surface-2:#202124;--line:#4a4b50;--text:#f7f7f8;--muted:#b7b8bd;color:var(--text);background:#202124}
    .pdv.pos-theme-minimum .pdv-main,.pdv.pos-theme-minimum .pdv-sidebar,.pdv.pos-theme-minimum .pdv-title,.pdv.pos-theme-minimum .pdv-footer,.pdv.pos-theme-minimum .pos-touch-shortcuts,.pdv.pos-theme-minimum .pos-touch-shortcuts button,.pdv.pos-theme-minimum .data-region,.pdv.pos-theme-minimum .data-table thead,.pdv.pos-theme-minimum .search-field input,.pdv.pos-theme-minimum .quantity-field input,.pdv.pos-theme-minimum .pos-widget,.pdv.pos-theme-minimum .suggestions,.pdv.pos-theme-minimum .suggestion,.pdv.pos-theme-minimum .pos-catalog-head,.pdv.pos-theme-minimum .pos-cart-panel>header,.pdv.pos-theme-minimum .pos-category-strip,.pdv.pos-theme-minimum .pos-category-strip button,.pdv.pos-theme-minimum .qty-stepper,.pdv.pos-theme-minimum .qty-stepper button,.pdv.pos-theme-minimum .qty-stepper input,.pdv.pos-theme-minimum .pos-cart-card,.pdv.pos-theme-minimum .pos-cart-mobile-edit,.pdv.pos-theme-minimum .company-badge,.pdv.pos-theme-minimum .language-switch,.pdv.pos-theme-minimum .shortcut-trigger{background:var(--surface);border-color:var(--line);color:var(--text);box-shadow:none}
    .pdv.pos-theme-minimum .pdv-main{background:#202124}
    .pdv.pos-theme-minimum .pos-product-grid,.pdv.pos-theme-minimum .pos-product-visual{background:#202124}
    .pdv.pos-theme-minimum .suggestion:hover,.pdv.pos-theme-minimum .pos-category-strip button.active{background:rgba(var(--accent-rgb),.14);color:#fff}
    .pdv.pos-theme-minimum .sync-pill.online{background:#173a2a;color:#7ce1ab}.pdv.pos-theme-minimum .sync-pill.pending{background:#493819;color:#f4cf72}.pdv.pos-theme-minimum .sync-pill.offline{background:#4b2026;color:#ff9ca8}
    .pdv.pos-theme-minimum .pdv-title{min-height:86px;position:relative;border-bottom:1px solid var(--line)}
    .pdv.pos-theme-minimum .pdv-title::after{content:'BUSQUE O ESCANEE EL PRODUCTO';position:absolute;left:50%;top:50%;max-width:44%;transform:translate(-50%,-50%);font-size:clamp(19px,2vw,32px);font-weight:900;letter-spacing:.06em;text-align:center;color:#fff;pointer-events:none}
    html[lang^="pt"] .pdv.pos-theme-minimum .pdv-title::after{content:'PASSE OU BUSQUE O PRODUTO'}
    .pdv.pos-theme-minimum .pdv-title h1{font-size:17px}
    .pdv.pos-theme-minimum .pdv-search{padding-block:18px}
    .pdv.pos-theme-minimum .pdv-search .search-field input{height:62px;border:2px solid #696a70;font-size:18px}
    .pdv.pos-theme-minimum .pdv-search .search-field:focus-within input{border-color:var(--accent);box-shadow:0 0 0 3px rgba(var(--accent-rgb),.18)}
    .pdv.pos-theme-minimum .quantity-field input{height:62px}
    .pdv.pos-theme-minimum .pos-client-strip{border-radius:9px;background:#292a2d;border-color:#4a4b50;box-shadow:none}
    .pdv.pos-theme-minimum .pos-client-strip-icon{border-radius:7px;background:#202124;box-shadow:none}
    .pdv.pos-theme-minimum .pos-sale-workspace{grid-template-columns:.86fr 1.14fr;gap:14px}
    .pdv.pos-theme-minimum .pos-catalog,.pdv.pos-theme-minimum .pos-cart-panel{border-radius:8px;border-color:var(--line);box-shadow:none}
    .pdv.pos-theme-minimum .pos-product-card{border-radius:7px;background:#292a2d;border-color:#4a4b50;box-shadow:none}
    .pdv.pos-theme-minimum .pos-product-card:hover{border-color:#77787e;transform:none;box-shadow:none}
    .pdv.pos-theme-minimum .pos-cart-panel header{background:#242528;border-color:var(--line)}
    .pdv.pos-theme-minimum .pdv-footer{border-color:var(--line)}
    .pdv.pos-theme-minimum .pdv-total{background:#191a1c;border:1px solid var(--line);border-radius:8px;padding:12px 18px}
    .pdv.pos-theme-minimum .pdv-total strong{font-size:34px}
    .pdv.pos-theme-minimum .pdv-sidebar{border-color:var(--line)}
    .pdv.pos-theme-minimum .pos-touch-shortcuts{gap:8px;padding:10px;border-top:1px solid var(--line)}
    .pdv.pos-theme-minimum .pos-touch-shortcuts button{min-height:88px;border:1px solid #595a60;border-radius:8px}
    .pdv.pos-theme-minimum .pos-touch-shortcuts button.finish{background:var(--accent);border-color:var(--accent);color:#fff}
    .pdv.pos-theme-minimum .pos-touch-shortcuts button:hover{border-color:#fff;transform:none}

    /* Venda rápida volta a recolher completamente e reabre pela aba lateral. */
    @media(min-width:981px){.pdv:not(.sidebar-collapsed){grid-template-columns:minmax(0,69.2%) minmax(300px,30.8%)!important}.pdv:not(.sidebar-collapsed) .pdv-sidebar{display:flex!important;padding:32px 24px 32px 32px!important;overflow:hidden!important}.pdv:not(.sidebar-collapsed) .pdv-side-head,.pdv:not(.sidebar-collapsed) .pdv-seller{display:block!important}.pdv:not(.sidebar-collapsed) .pdv-links{padding:20px 0 0!important;display:block!important}.pdv:not(.sidebar-collapsed) .pdv-links li{min-height:56px!important}.pdv:not(.sidebar-collapsed) .pos-widget{width:100%!important;height:auto!important;min-height:48px;padding:0 12px!important;display:flex!important;justify-content:flex-start!important}.pdv:not(.sidebar-collapsed) .pos-widget>span{display:inline!important}.pdv:not(.sidebar-collapsed) .pos-widget>span:last-child{margin-left:auto!important}.pdv:not(.sidebar-collapsed) .pos-panel-toggle{top:17px!important;right:14px!important;width:auto!important;height:32px!important;padding:0 10px!important;transform:none!important}.pdv:not(.sidebar-collapsed) .pos-panel-toggle span{display:inline!important}.pdv:not(.sidebar-collapsed) .pos-panel-toggle:before{transform:rotate(180deg)!important}.pdv.sidebar-collapsed{grid-template-columns:minmax(0,1fr)!important}.pdv.sidebar-collapsed .pdv-main{border-right:0!important}.pdv.sidebar-collapsed .pdv-sidebar{display:none!important}.pdv.sidebar-collapsed .pos-panel-reopen{display:flex!important}}
    .pdv.dock-footer,.pdv.dock-footer.sidebar-collapsed{grid-template-columns:minmax(0,1fr)!important}.pdv.dock-footer .pdv-main{border-right:0!important}.pdv.dock-footer .pdv-sidebar,.pdv.dock-footer .pos-panel-toggle,.pdv.dock-footer .pos-panel-reopen{display:none!important}

    @media(max-width:1100px){.pdv.pos-theme-minimum .pdv-title::after{display:none}.pdv.pos-theme-minimum .pos-sale-workspace{grid-template-columns:1fr}}
    @media(max-width:720px){html[data-scale="large"]{font-size:16px}html[data-scale="large"] .page-title,html[data-scale="large"] .page-title h1{font-size:30px!important}html[data-scale="large"] .btn,html[data-scale="large"] input:not([type="radio"]):not([type="checkbox"]),html[data-scale="large"] select{min-height:50px;font-size:15px!important}html[data-scale="large"] .data-table td{height:58px;font-size:14px!important}html[data-scale="large"] .pos-touch-shortcuts button{min-height:76px}.pdv.pos-theme-minimum .pdv-search{padding-block:10px}.pdv.pos-theme-minimum .pdv-search .search-field input{height:56px}.pdv.pos-theme-minimum .pos-touch-shortcuts{gap:6px;padding:7px}.pdv.pos-theme-minimum .pos-touch-shortcuts button{min-height:72px}}
  `;
  document.head.append(clientStyles);

  function openDedicatedPdv() {
    sessionStorage.setItem('floralis.pos.unlocked', '1');
    const url = new URL('./pdv.html?source=dedicated-window', window.location.href);
    const pdvWindow = window.open(url.href, 'floralis-pdv', 'popup=yes,width=1440,height=900,resizable=yes,scrollbars=yes');
    pdvWindow?.focus();
  }

  document.addEventListener('click', event => {
    const pdvLink = event.target.closest?.('a[href*="pdv.html"]');
    if (pdvLink) sessionStorage.setItem('floralis.pos.unlocked', '1');

    const action = event.target.closest?.('[data-action]')?.dataset.action;
    if (!adminMode || globalThis.FLORALIS_NATIVE_APP || action !== 'open-pos') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    openDedicatedPdv();
  }, true);

  document.addEventListener('keydown', event => {
    const typing = ['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target?.tagName);
    if (!adminMode || globalThis.FLORALIS_NATIVE_APP || typing || event.key !== 'F3') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    openDedicatedPdv();
  }, true);

  function syncPdvPanel() {
    if (!layer) return;
    const isPdvPanel = document.body.dataset.mode === 'standalone-pos' && !layer.hidden && Boolean(
      layer.querySelector('#posClientForm, #posNotesForm, #posDeliveryForm, .pos-client-picker-head')
    );
    layer.classList.toggle('pdv-context-layer', isPdvPanel);
  }

  function syncCollapsedWidgets() {
    document.querySelectorAll('.pdv-sidebar [data-pos-widget]').forEach(button => {
      const label = button.querySelector('[data-pos-widget-label]')?.textContent?.trim();
      if (label) button.title = label;
    });
  }

  function syncFooterDockState() {
    const pdv = document.querySelector('.pdv.dock-footer.sidebar-collapsed');
    const toggle = pdv?.querySelector('[data-action="toggle-pos-panel"]');
    if (!pdv || !toggle || pdv.dataset.footerDockReset === 'pending') return;
    pdv.dataset.footerDockReset = 'pending';
    queueMicrotask(() => {
      if (pdv.isConnected && pdv.matches('.dock-footer.sidebar-collapsed')) toggle.click();
    });
  }

  function currentClientName() {
    const label = document.querySelector('.pdv [data-pos-widget="client"] [data-pos-widget-label]')?.textContent?.trim();
    return label && label !== 'Cliente' ? label : '';
  }

  function ensureClientStrip() {
    const pdv = document.querySelector('.pdv');
    const search = pdv?.querySelector('.pdv-search');
    if (!pdv || !search || pdv.querySelector('.pos-client-strip')) return;
    const name = currentClientName();
    const strip = document.createElement('section');
    strip.className = `pos-client-strip${name ? ' selected' : ''}`;
    strip.setAttribute('aria-label', 'Cliente de la venta');
    strip.innerHTML = `<span class="pos-client-strip-icon">${clientIcon}</span><div class="pos-client-strip-copy"><small>CLIENTE DE LA VENTA</small><strong>${name || 'Consumidor final'}</strong><span>${name ? 'Cliente seleccionado' : 'Busque o registre un cliente sin salir del PDV'}</span></div>${name ? '<button class="btn small" type="button" data-pdv-client-clear>Consumidor final</button>' : ''}<button class="btn secondary" type="button" data-pdv-client-search>${name ? 'Cambiar' : 'Buscar cliente'}</button><button class="btn primary" type="button" data-pdv-client-new>Nuevo cliente</button>`;
    search.insertAdjacentElement('afterend', strip);
  }

  function filterClientRows(value = '') {
    const term = clientSearchKey(value);
    const rows = [...document.querySelectorAll('[data-pos-client-row]')];
    let visible = 0;
    rows.forEach(row => {
      const show = !term || clientSearchKey(row.dataset.search).includes(term);
      row.hidden = !show;
      if (show) visible += 1;
    });
    const empty = document.getElementById('posClientSearchEmpty');
    if (empty) empty.hidden = visible > 0 || rows.length === 0;
    const count = document.getElementById('posClientCount');
    if (count) count.textContent = `${visible} ${visible === 1 ? 'cliente' : 'clientes'}`;
  }

  function enhanceClientPicker() {
    const head = document.querySelector('.pos-client-picker-head:not([data-pdv-enhanced])');
    if (!head) return;
    head.dataset.pdvEnhanced = 'true';
    const selectedName = currentClientName();
    const helper = head.querySelector('small');
    if (helper) helper.textContent = 'Busque, seleccione o registre un cliente. El carrito permanecerá abierto.';
    const count = document.createElement('b');
    count.id = 'posClientCount';
    head.querySelector('.btn')?.before(count);
    const input = document.getElementById('posClientSearch');
    const field = input?.closest('.field');
    if (input && field) {
      field.classList.add('pos-client-search-field');
      input.placeholder = 'Nombre, código, CI/NIT o celular';
      input.autocomplete = 'off';
      const box = document.createElement('div');
      box.className = 'pos-client-search-box';
      box.innerHTML = searchIcon;
      input.before(box);
      box.append(input);
    }
    const region = head.parentElement?.querySelector('.data-region');
    if (region) {
      region.classList.add('pos-client-results');
      const consumer = document.createElement('button');
      consumer.type = 'button';
      consumer.className = `pos-consumer-final${selectedName ? '' : ' selected'}`;
      consumer.dataset.selectClient = '';
      consumer.innerHTML = `<span>${clientIcon}</span><div><strong>Consumidor final</strong><small>Venta rápida sin vincular a una cuenta</small></div><b>${selectedName ? 'Usar' : 'Seleccionado'}</b>`;
      region.before(consumer);
    }
    document.querySelectorAll('[data-pos-client-row]').forEach(row => {
      const name = row.querySelector('td strong')?.textContent?.trim();
      if (selectedName && name === selectedName) row.classList.add('selected');
    });
    filterClientRows(input?.value);
    input?.focus();
  }

  function renderPdvProfileChooser(form, input) {
    if (document.body.dataset.mode !== 'standalone-pos' || form.querySelector('.pdv-profile-login')) return;
    const profiles = readPdvProfiles();
    if (!profiles.length) return;
    const usernameField = input.closest('.field');
    const passwordField = form.elements.password?.closest('.field');
    const chooser = document.createElement('section');
    chooser.className = 'pdv-profile-login';
    const heading = document.createElement('div');
    heading.className = 'pdv-profile-heading';
    const title = document.createElement('strong');
    title.textContent = document.documentElement.lang.startsWith('pt') ? 'Quem vai usar o PDV?' : '¿Quién va a usar el PDV?';
    const helper = document.createElement('small');
    helper.textContent = document.documentElement.lang.startsWith('pt') ? 'Escolha seu perfil e digite apenas a senha.' : 'Elija su perfil e ingrese solamente la contraseña.';
    heading.append(title, helper);
    const grid = document.createElement('div');
    grid.className = 'pdv-profile-grid';

    function selectProfile(profile, button) {
      grid.querySelectorAll('.pdv-profile-card').forEach(card => card.classList.toggle('active', card === button));
      input.value = profile?.email || '';
      usernameField.hidden = Boolean(profile);
      passwordField?.querySelector('input')?.focus();
    }

    profiles.forEach((profile, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `pdv-profile-card${index === 0 ? ' active' : ''}`;
      const avatar = document.createElement('span');
      avatar.textContent = String(profile.name).trim().charAt(0).toUpperCase() || '?';
      const name = document.createElement('strong');
      name.textContent = profile.name;
      const role = document.createElement('small');
      role.textContent = profile.role === 'admin' ? 'Administrador' : document.documentElement.lang.startsWith('pt') ? 'Funcionário' : 'Funcionario';
      button.append(avatar, name, role);
      button.addEventListener('click', () => selectProfile(profile, button));
      grid.append(button);
    });

    const other = document.createElement('button');
    other.type = 'button';
    other.className = 'pdv-profile-card pdv-profile-other';
    const plus = document.createElement('span');
    plus.textContent = '+';
    const otherName = document.createElement('strong');
    otherName.textContent = document.documentElement.lang.startsWith('pt') ? 'Outro usuário' : 'Otro usuario';
    const otherHelp = document.createElement('small');
    otherHelp.textContent = document.documentElement.lang.startsWith('pt') ? 'Usar novo acesso' : 'Usar nuevo acceso';
    other.append(plus, otherName, otherHelp);
    other.addEventListener('click', () => {
      grid.querySelectorAll('.pdv-profile-card').forEach(card => card.classList.toggle('active', card === other));
      input.value = '';
      usernameField.hidden = false;
      input.focus();
    });
    grid.append(other);
    chooser.append(heading, grid);
    usernameField.before(chooser);
    selectProfile(profiles[0], grid.firstElementChild);
  }

  function enhanceLogin() {
    const form = document.getElementById('loginForm');
    const input = form?.elements?.email;
    if (!input || input.dataset.usernameEnabled) return;
    input.dataset.usernameEnabled = 'true';
    input.type = 'text';
    input.autocomplete = 'username';
    input.placeholder = document.documentElement.lang.startsWith('pt') ? 'Digite seu usuário' : 'Ingrese su usuario';
    const label = input.closest('.field')?.querySelector('label');
    if (label) label.textContent = document.documentElement.lang.startsWith('pt') ? 'Usuário' : 'Usuario';
    renderPdvProfileChooser(form, input);
  }

  function ensureMinimumOptions() {
    const appearanceForm = document.getElementById('appearanceForm');
    const shellGrid = appearanceForm?.querySelector('.shell-choice-grid');
    const largeScaleDescription = appearanceForm?.querySelector('input[name="scale"][value="large"]')?.closest('.interface-scale-option')?.querySelector('small');
    if (largeScaleDescription && !largeScaleDescription.dataset.largeCopy) {
      largeScaleDescription.dataset.largeCopy = 'true';
      largeScaleDescription.textContent = 'Leitura realmente grande e proporcional';
    }
    if (shellGrid && !shellGrid.querySelector('input[value="minimum"]')) {
      const selected = document.documentElement.dataset.shell === 'minimum';
      if (selected) shellGrid.querySelectorAll('input[name="shell"]').forEach(input => { input.checked = false; });
      const choice = document.createElement('label');
      choice.className = `shell-choice${selected ? ' active' : ''}`;
      choice.innerHTML = `<input type="radio" name="shell" value="minimum" ${selected ? 'checked' : ''}><span class="shell-preview shell-preview-minimum"><i></i><b></b><em></em></span><div><strong>Minimum</strong><small>Visual amplo, escuro e direto, com a identidade FLORALIS.</small></div>`;
      shellGrid.append(choice);
    }

    const layoutForm = document.getElementById('posLayoutForm');
    const themeSelect = layoutForm?.elements?.theme;
    if (themeSelect && !themeSelect.querySelector('option[value="minimum"]')) {
      const option = document.createElement('option');
      option.value = 'minimum';
      option.textContent = 'Minimum FLORALIS';
      themeSelect.append(option);
      if (layoutForm.querySelector('.pos-theme-preview.theme-minimum')) themeSelect.value = 'minimum';
    }
  }

  function clarifySaleReceiptSetting() {
    document.querySelector('[data-sale-print-format]')?.closest('.field')?.remove();
    const select = document.querySelector('select[name="saleReceiptTemplate"]');
    if (!select || select.dataset.officialReceiptCopy) return;
    select.dataset.officialReceiptCopy = 'true';
    const field = select.closest('.field');
    const label = field?.querySelector('label');
    const helper = field?.querySelector('small');
    if (label) label.textContent = 'Modelo del recibo de venta';
    if (select.options[0]) select.options[0].textContent = 'Formulario oficial tabular — modelo principal enviado';
    if (select.options[1]) select.options[1].textContent = 'Recibo oficial tabular — modelo anterior';
    if (helper) helper.textContent = 'Este modelo A4 se mostrará e imprimirá al finalizar una venta. No se usará cupón térmico.';
  }

  function syncExperience() {
    syncClientFlow();
    enhanceLogin();
    ensureMinimumOptions();
    clarifySaleReceiptSetting();
    syncFooterDockState();
  }

  function syncClientFlow() {
    ensureClientStrip();
    enhanceClientPicker();
  }

  document.addEventListener('click', event => {
    const clear = event.target.closest?.('[data-pdv-client-clear]');
    const search = event.target.closest?.('[data-pdv-client-search]');
    const create = event.target.closest?.('[data-pdv-client-new]');
    if (!clear && !search && !create) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (clear) window.finishClientSelection?.('');
    if (search) window.posClientPicker?.();
    if (create) window.posClientForm?.();
  }, true);

  document.addEventListener('input', event => {
    if (event.target?.id === 'posClientSearch') filterClientRows(event.target.value);
  }, true);

  document.addEventListener('change', event => {
    if (event.target?.matches?.('#appearanceForm input[name="shell"]')) {
      document.documentElement.dataset.shell = event.target.value;
      event.target.closest('.shell-choice-grid')?.querySelectorAll('.shell-choice').forEach(choice => choice.classList.toggle('active', choice.contains(event.target)));
    }
    if (event.target?.matches?.('#posLayoutForm select[name="theme"]')) {
      const preview = event.target.form?.querySelector('.pos-theme-preview');
      if (preview) preview.className = `pos-theme-preview theme-${event.target.value}`;
    }
    if (event.target?.matches?.('#posLayoutForm select[name="palette"],#posAppearanceForm select[name="palette"]')) {
      const preview = event.target.form?.querySelector('.pos-color-preview');
      if (preview) {
        preview.dataset.posColorPreview = event.target.value;
        preview.querySelectorAll('[data-pos-preview-color]').forEach(item => item.classList.toggle('active', item.dataset.posPreviewColor === event.target.value));
      }
    }
  }, true);

  if (layer) new MutationObserver(() => { syncPdvPanel(); syncExperience(); }).observe(layer, {attributes: true, childList: true, subtree: true, attributeFilter: ['hidden']});
  if (app) new MutationObserver(() => { syncCollapsedWidgets(); syncExperience(); }).observe(app, {childList: true, subtree: true});
  syncPdvPanel();
  syncCollapsedWidgets();
  syncExperience();
})();
