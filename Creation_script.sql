-- ===========================================
-- EXTENSIONES
-- ===========================================
CREATE EXTENSION IF NOT EXISTS citext;

-- ===========================================
-- FUNCION DE VERSIONADO Y UPDATED_AT
-- ===========================================
CREATE OR REPLACE FUNCTION set_updated_at() 
RETURNS trigger 
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  NEW.id_version := COALESCE(OLD.id_version, 0) + 1;
  RETURN NEW;
END $$;

-- ===========================================
-- ARCHIVOS
-- ===========================================
CREATE TABLE IF NOT EXISTS archivos (
  file_id         BIGSERIAL PRIMARY KEY,
  tipo            VARCHAR(40) NOT NULL,
  storage_url     TEXT NOT NULL,
  mime_type       VARCHAR(100),
  size_in_bytes   BIGINT,
  estado          VARCHAR(20) NOT NULL DEFAULT 'activo',
  register_status TEXT NOT NULL DEFAULT 'activo',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version      INT NOT NULL DEFAULT 1,
  CONSTRAINT chk_tipo
    CHECK (tipo IN ('doc_campana', 'portada', 'imagen', 'video')),
  CONSTRAINT chk_estado
    CHECK (estado IN ('activo', 'eliminado')),
  CONSTRAINT archivos_ck_register_status
    CHECK (register_status IN ('activo','inactivo'))
);

DROP TRIGGER IF EXISTS trg_archivos_upd ON archivos;
CREATE TRIGGER trg_archivos_upd
BEFORE UPDATE ON archivos
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- ESQUEMA USUARIOS
-- ===========================================
CREATE SCHEMA IF NOT EXISTS usuarios;

CREATE TABLE IF NOT EXISTS usuarios.usuarios (
  user_id              BIGSERIAL PRIMARY KEY,
  email                CITEXT UNIQUE NOT NULL,
  telefono             VARCHAR(30),
  password_hash        TEXT NOT NULL,
  estado               VARCHAR(20) NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'suspendido', 'cerrado')), 
  pais                 VARCHAR(20),
  puede_crear_campanas BOOLEAN NOT NULL DEFAULT FALSE,
  ultimo_login_at      TIMESTAMPTZ,
  register_status      TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version           INT NOT NULL DEFAULT 1
);

DROP TRIGGER IF EXISTS trg_usuarios_upd ON usuarios.usuarios;
CREATE TRIGGER trg_usuarios_upd
BEFORE UPDATE ON usuarios.usuarios
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS usuarios.cuentas_bancarias (
  bank_account_id        BIGSERIAL PRIMARY KEY,
  user_id                BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  titular                VARCHAR(120) NOT NULL,
  banco                  VARCHAR(120),
  account_alias          VARCHAR(80),
  account_number_masked  VARCHAR(30) NOT NULL,
  tipo                   VARCHAR(30),
  moneda                 VARCHAR(3) NOT NULL,
  register_status        TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version             INT NOT NULL DEFAULT 1
);

DROP TRIGGER IF EXISTS trg_cuentas_bancarias_upd ON usuarios.cuentas_bancarias;
CREATE TRIGGER trg_cuentas_bancarias_upd
BEFORE UPDATE ON usuarios.cuentas_bancarias
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS usuarios.usuarios_persona_natural (
  user_id             BIGINT PRIMARY KEY REFERENCES usuarios.usuarios(user_id) ON DELETE CASCADE,
  nombre              VARCHAR(80) NOT NULL,
  apellido            VARCHAR(80) NOT NULL,
  fecha_nacimiento    DATE,
  direccion_linea1    VARCHAR(200),
  ciudad              VARCHAR(80),
  estado_provincia    VARCHAR(80),
  codigo_postal       VARCHAR(20),
  register_status     TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version          INT NOT NULL DEFAULT 1
);

DROP TRIGGER IF EXISTS trg_usuarios_persona_natural_upd ON usuarios.usuarios_persona_natural;
CREATE TRIGGER trg_usuarios_persona_natural_upd
BEFORE UPDATE ON usuarios.usuarios_persona_natural
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS usuarios.usuarios_empresa (
  user_id            BIGINT PRIMARY KEY REFERENCES usuarios.usuarios(user_id) ON DELETE CASCADE,
  razon_social       VARCHAR(160) NOT NULL,
  registro_mercantil VARCHAR(60),
  direccion_fiscal   VARCHAR(200),
  register_status    TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version         INT NOT NULL DEFAULT 1
);

DROP TRIGGER IF EXISTS trg_usuarios_empresa_upd ON usuarios.usuarios_empresa;
CREATE TRIGGER trg_usuarios_empresa_upd
BEFORE UPDATE ON usuarios.usuarios_empresa
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS usuarios.beneficial_owners (
  bo_id                     BIGSERIAL PRIMARY KEY,
  empresa_id                BIGINT NOT NULL REFERENCES usuarios.usuarios_empresa(user_id) ON DELETE CASCADE,
  persona_id                BIGINT NOT NULL REFERENCES usuarios.usuarios_persona_natural(user_id) ON DELETE CASCADE,
  porcentaje_participacion  NUMERIC(5,2)
    CHECK (porcentaje_participacion > 0 AND porcentaje_participacion <= 100),
  tipo_control              VARCHAR(20) NOT NULL,
  register_status           TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version                INT NOT NULL DEFAULT 1,
  CONSTRAINT uq_bo_empresa_persona UNIQUE (empresa_id, persona_id),
  CONSTRAINT bo_ck_tipo_control CHECK (tipo_control IN ('directo','indirecto','rep_legal'))
);

DROP TRIGGER IF EXISTS trg_beneficial_owners_upd ON usuarios.beneficial_owners;
CREATE TRIGGER trg_beneficial_owners_upd
BEFORE UPDATE ON usuarios.beneficial_owners
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- ESQUEMA CAMPANAS
-- ===========================================
CREATE SCHEMA IF NOT EXISTS campanas;

CREATE TABLE IF NOT EXISTS campanas.campanas (
  campaign_id            BIGSERIAL PRIMARY KEY,
  titulo                 VARCHAR(160) NOT NULL,
  descripcion_corta      VARCHAR(300),
  descripcion_larga      TEXT,
  usuario_solicitante_id BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  beneficiario_id        BIGINT REFERENCES usuarios.usuarios(user_id),
  monto_solicitado       NUMERIC(18,2) NOT NULL CHECK (monto_solicitado > 0),
  moneda                 VARCHAR(3) NOT NULL,
  fecha_limite           DATE NOT NULL,
  categoria              VARCHAR(80),
  pais                   VARCHAR(20),
  ciudad                 VARCHAR(80),
  metodo_financiamiento  VARCHAR(20) NOT NULL DEFAULT 'all_or_nothing', 
  tipo_campana           VARCHAR(20) NOT NULL DEFAULT 'donacion',        
  finalidad_fondos       VARCHAR(400),
  video_url              TEXT,
  portada_file_id        BIGINT REFERENCES archivos(file_id),
  estado                 VARCHAR(20) NOT NULL DEFAULT 'borrador',
  register_status        TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at           TIMESTAMPTZ,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version             INT NOT NULL DEFAULT 1,
  CONSTRAINT campanas_ck_metodo_financiamiento
    CHECK (metodo_financiamiento IN ('all_or_nothing','flexible')),
  CONSTRAINT campanas_ck_tipo_campana
    CHECK (tipo_campana IN ('donacion','recompensa','prestamo','equity')),
  CONSTRAINT campanas_ck_estado
    CHECK (estado IN ('borrador','en_revision','aprobada','rechazada','publicada','pausada','finalizada','cancelada','eliminada'))
);

DROP TRIGGER IF EXISTS trg_campanas_upd ON campanas.campanas;
CREATE TRIGGER trg_campanas_upd
BEFORE UPDATE ON campanas.campanas
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS campanas.campanas_x_archivos(
    campaign_id     BIGINT REFERENCES campanas.campanas(campaign_id),
    file_id         BIGINT REFERENCES archivos(file_id),
    register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_version      INT NOT NULL DEFAULT 1,
    CONSTRAINT pk_campanas_x_archivos PRIMARY KEY (campaign_id, file_id)
);

DROP TRIGGER IF EXISTS trg_campanas_x_archivos_upd ON campanas.campanas_x_archivos;
CREATE TRIGGER trg_campanas_x_archivos_upd
BEFORE UPDATE ON campanas.campanas_x_archivos
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS campanas_solicitante_idx ON campanas.campanas (usuario_solicitante_id);
CREATE INDEX IF NOT EXISTS campanas_estado_idx ON campanas.campanas (estado);
CREATE INDEX IF NOT EXISTS campanas_pais_ciudad_idx ON campanas.campanas (pais, ciudad);
CREATE INDEX IF NOT EXISTS campanas_published_idx ON campanas.campanas (published_at);

-- ===========================================
-- APROBACIONES (INMUTABLES)
-- ===========================================
CREATE TABLE IF NOT EXISTS campanas.campana_aprobaciones (
  campaign_approval_id BIGSERIAL PRIMARY KEY,
  campaign_id          BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id),
  aprobador_id         BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  decision             VARCHAR(20) NOT NULL,
  motivo               TEXT,
  revision_notes       TEXT,
  decidida_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT camp_aprob_ck_decision
    CHECK (decision IN ('aprobada','rechazada'))
);

/* Índice útil (eliminado el UNIQUE inválido sobre columna inexistente 'version')
-- Si quieres evitar duplicados por campaña, podrías:
-- CREATE UNIQUE INDEX IF NOT EXISTS campana_aprobaciones_unq ON campanas.campana_aprobaciones (campaign_id);
*/

-- ===========================================
-- UPDATES Y COMENTARIOS
-- ===========================================
CREATE TABLE IF NOT EXISTS campanas.campaign_updates (
  campaign_update_id BIGSERIAL PRIMARY KEY,
  campaign_id        BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id) ON DELETE CASCADE,
  autor_id           BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  contenido          TEXT NOT NULL,
  register_status    TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version         INT NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS campaign_updates_campaign_idx ON campanas.campaign_updates (campaign_id);
CREATE INDEX IF NOT EXISTS campaign_updates_autor_idx ON campanas.campaign_updates (autor_id);

DROP TRIGGER IF EXISTS trg_campaign_updates_upd ON campanas.campaign_updates;
CREATE TRIGGER trg_campaign_updates_upd
BEFORE UPDATE ON campanas.campaign_updates
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS campanas.comentarios (
  comment_id         BIGSERIAL PRIMARY KEY,
  campaign_id        BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id) ON DELETE CASCADE,
  autor_id           BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  texto              TEXT NOT NULL,
  moderation_status  VARCHAR(20) NOT NULL DEFAULT 'visible',
  register_status    TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version         INT NOT NULL DEFAULT 1,
  CONSTRAINT comentarios_ck_moderation
    CHECK (moderation_status IN ('visible','oculto','eliminado'))
);

CREATE INDEX IF NOT EXISTS comentarios_campaign_idx ON campanas.comentarios (campaign_id);
CREATE INDEX IF NOT EXISTS comentarios_autor_idx ON campanas.comentarios (autor_id);

DROP TRIGGER IF EXISTS trg_comentarios_upd ON campanas.comentarios;
CREATE TRIGGER trg_comentarios_upd
BEFORE UPDATE ON campanas.comentarios
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- REPORTES (revision)
-- ===========================================
CREATE SCHEMA IF NOT EXISTS revision;

CREATE TABLE IF NOT EXISTS revision.reportes (
  report_id     BIGSERIAL PRIMARY KEY,
  target_tipo   VARCHAR(20) NOT NULL,  -- campana|comentario|usuario
  target_id     BIGINT NOT NULL,
  reporter_id   BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  motivo        VARCHAR(160),
  estado        VARCHAR(20) NOT NULL DEFAULT 'pendiente',
  resuelto_por  BIGINT REFERENCES usuarios.usuarios(user_id),
  resuelto_at   TIMESTAMPTZ,
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version    INT NOT NULL DEFAULT 1,
  CONSTRAINT reportes_ck_target_tipo
    CHECK (target_tipo IN ('campana','comentario','usuario')),
  CONSTRAINT reportes_ck_estado
    CHECK (estado IN ('pendiente','en_revision','resuelto','descartado'))
);

CREATE INDEX IF NOT EXISTS reportes_target_idx ON revision.reportes (target_tipo, target_id);

DROP TRIGGER IF EXISTS trg_reportes_upd ON revision.reportes;
CREATE TRIGGER trg_reportes_upd
BEFORE UPDATE ON revision.reportes
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- REWARD TIERS
-- ===========================================
CREATE TABLE IF NOT EXISTS campanas.reward_tiers (
  reward_tier_id  BIGSERIAL PRIMARY KEY,
  campaign_id     BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id) ON DELETE CASCADE,
  titulo          VARCHAR(120) NOT NULL,
  descripcion     TEXT,
  monto_minimo    NUMERIC(18,2) NOT NULL CHECK (monto_minimo > 0),
  stock_total     INT,
  stock_reservado INT NOT NULL DEFAULT 0,
  fecha_entrega_estimada DATE,
  costo_envio     NUMERIC(18,2),
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version      INT NOT NULL DEFAULT 1,
  CONSTRAINT reward_tiers_ck_stock
    CHECK (stock_total IS NULL OR stock_total >= 0),
  CONSTRAINT reward_tiers_ck_reservado
    CHECK (stock_reservado >= 0 AND (stock_total IS NULL OR stock_reservado <= stock_total))
);

CREATE INDEX IF NOT EXISTS reward_tiers_campaign_idx ON campanas.reward_tiers (campaign_id);

DROP TRIGGER IF EXISTS trg_reward_tiers_upd ON campanas.reward_tiers;
CREATE TRIGGER trg_reward_tiers_upd
BEFORE UPDATE ON campanas.reward_tiers
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- PLEDGES
-- ===========================================
CREATE TABLE IF NOT EXISTS campanas.pledges (
  pledge_id      BIGSERIAL PRIMARY KEY,
  campaign_id    BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id),
  donante_id     BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  reward_tier_id BIGINT REFERENCES campanas.reward_tiers(reward_tier_id),
  monto          NUMERIC(18,2) NOT NULL CHECK (monto > 0),
  moneda         VARCHAR(3) NOT NULL,
  anonima        BOOLEAN DEFAULT FALSE,
  mensaje        VARCHAR(300),
  estado         VARCHAR(20) NOT NULL DEFAULT 'iniciada', -- iniciada|pagada|fallida|reembolsada|cancelada
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version     INT NOT NULL DEFAULT 1,
  CONSTRAINT pledges_ck_estado
    CHECK (estado IN ('iniciada','pagada','fallida','reembolsada','cancelada'))
);

CREATE INDEX IF NOT EXISTS pledges_campaign_idx ON campanas.pledges (campaign_id);
CREATE INDEX IF NOT EXISTS pledges_donante_idx ON campanas.pledges (donante_id);
CREATE INDEX IF NOT EXISTS pledges_estado_idx ON campanas.pledges (estado);

DROP TRIGGER IF EXISTS trg_pledges_upd ON campanas.pledges;
CREATE TRIGGER trg_pledges_upd
BEFORE UPDATE ON campanas.pledges
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- ESQUEMA CONTABILIDAD
-- ===========================================
CREATE SCHEMA IF NOT EXISTS contabilidad;

CREATE TABLE IF NOT EXISTS contabilidad.pagos (
  payment_id     BIGSERIAL PRIMARY KEY,
  pledge_id      BIGINT NOT NULL UNIQUE REFERENCES campanas.pledges(pledge_id) ON DELETE CASCADE,
  metodo_pago    VARCHAR(40) NOT NULL, -- tarjeta|transferencia|wallet|...
  estado         VARCHAR(20) NOT NULL, -- autorizado|capturado|fallido|reembolsado|chargeback
  monto_bruto    NUMERIC(18,2) NOT NULL,
  tarifa_plat    NUMERIC(18,2) NOT NULL DEFAULT 0,
  tarifa_gateway NUMERIC(18,2) NOT NULL DEFAULT 0,
  monto_neto     NUMERIC(18,2) GENERATED ALWAYS AS (monto_bruto - tarifa_plat - tarifa_gateway) STORED,
  moneda         VARCHAR(3) NOT NULL,
  autorizado_at  TIMESTAMPTZ,
  capturado_at   TIMESTAMPTZ,
  reembolsado_at TIMESTAMPTZ,
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version     INT NOT NULL DEFAULT 1,
  CONSTRAINT pagos_ck_estado
    CHECK (estado IN ('autorizado','capturado','fallido','reembolsado','chargeback')),
  CONSTRAINT pagos_ck_neto_no_negativo
    CHECK (monto_neto >= 0)
);

DROP TRIGGER IF EXISTS trg_pagos_upd ON contabilidad.pagos;
CREATE TRIGGER trg_pagos_upd
BEFORE UPDATE ON contabilidad.pagos
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS pagos_estado_idx ON contabilidad.pagos (estado);
CREATE INDEX IF NOT EXISTS pagos_autorizado_idx ON contabilidad.pagos (autorizado_at);
CREATE INDEX IF NOT EXISTS pagos_capturado_idx ON contabilidad.pagos (capturado_at);

CREATE TABLE IF NOT EXISTS contabilidad.payout_batches (
  batch_id    BIGSERIAL PRIMARY KEY,
  moneda      VARCHAR(3) NOT NULL,
  estado      VARCHAR(20) NOT NULL DEFAULT 'abierto', -- abierto|enviado|cerrado
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version  INT NOT NULL DEFAULT 1,
  CONSTRAINT payout_batches_ck_estado
    CHECK (estado IN ('abierto','enviado','cerrado'))
);

DROP TRIGGER IF EXISTS trg_payout_batches_upd ON contabilidad.payout_batches;
CREATE TRIGGER trg_payout_batches_upd
BEFORE UPDATE ON contabilidad.payout_batches
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS contabilidad.desembolsos (
  payout_id        BIGSERIAL PRIMARY KEY,
  campaign_id      BIGINT NOT NULL REFERENCES campanas.campanas(campaign_id),
  beneficiario_id  BIGINT NOT NULL REFERENCES usuarios.usuarios(user_id),
  bank_account_id  BIGINT NOT NULL REFERENCES usuarios.cuentas_bancarias(bank_account_id),
  batch_id         BIGINT REFERENCES contabilidad.payout_batches(batch_id),
  monto_bruto      NUMERIC(18,2) NOT NULL CHECK (monto_bruto > 0),
  tarifa_transferencia NUMERIC(18,2) NOT NULL DEFAULT 0,
  monto_neto       NUMERIC(18,2) GENERATED ALWAYS AS (monto_bruto - tarifa_transferencia) STORED,
  moneda           VARCHAR(3) NOT NULL,
  estado           VARCHAR(20) NOT NULL DEFAULT 'pendiente', -- pendiente|procesando|pagado|fallido
  programado_at    TIMESTAMPTZ,
  pagado_at        TIMESTAMPTZ,
  register_status  TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version       INT NOT NULL DEFAULT 1,
  CONSTRAINT desembolsos_ck_estado
    CHECK (estado IN ('pendiente','procesando','pagado','fallido'))
);

CREATE INDEX IF NOT EXISTS desembolsos_batch_idx ON contabilidad.desembolsos (batch_id);
CREATE INDEX IF NOT EXISTS desembolsos_campaign_idx ON contabilidad.desembolsos (campaign_id);
CREATE INDEX IF NOT EXISTS desembolsos_benef_idx ON contabilidad.desembolsos (beneficiario_id);

DROP TRIGGER IF EXISTS trg_desembolsos_upd ON contabilidad.desembolsos;
CREATE TRIGGER trg_desembolsos_upd
BEFORE UPDATE ON contabilidad.desembolsos
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ===========================================
-- LEDGER (DOBLE PARTIDA) - INMUTABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS ledger_entries (
  entry_id         BIGSERIAL PRIMARY KEY,
  fecha            TIMESTAMPTZ NOT NULL DEFAULT now(),
  cuenta_debito    VARCHAR(60) NOT NULL,
  cuenta_credito   VARCHAR(60) NOT NULL,
  monto            NUMERIC(18,2) NOT NULL CHECK (monto > 0),
  moneda           VARCHAR(3) NOT NULL,
  referencia_tipo  VARCHAR(40) NOT NULL,  -- Payment|Payout|Refund|Fee...
  referencia_id    BIGINT NOT NULL,
  CHECK (cuenta_debito <> cuenta_credito)
);

-- ===========================================
-- SUPERUSUARIOS DE APP
-- ===========================================
CREATE TABLE IF NOT EXISTS app_superusers (
  user_id       BIGINT PRIMARY KEY REFERENCES usuarios.usuarios(user_id) ON DELETE CASCADE,
  granted_by    BIGINT REFERENCES usuarios.usuarios(user_id) ON DELETE SET NULL,
  granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ,
  is_revoked    BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_by    BIGINT REFERENCES usuarios.usuarios(user_id) ON DELETE SET NULL,
  revoked_at    TIMESTAMPTZ,
  revoke_reason VARCHAR(50),
  reason        VARCHAR(50),
  register_status TEXT NOT NULL DEFAULT 'activo' CHECK (register_status IN ('activo','inactivo')),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  id_version    INT NOT NULL DEFAULT 1,
  CONSTRAINT app_superusers_ck_expires_after_granted
    CHECK (expires_at IS NULL OR expires_at > granted_at),
  CONSTRAINT app_superusers_ck_revocation_fields
    CHECK (
      (is_revoked = FALSE AND revoked_by IS NULL AND revoked_at IS NULL AND revoke_reason IS NULL)
      OR
      (is_revoked = TRUE  AND revoked_at IS NOT NULL)
    )
);

DROP TRIGGER IF EXISTS trg_app_superusers_upd ON app_superusers;
CREATE TRIGGER trg_app_superusers_upd
BEFORE UPDATE ON app_superusers
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS app_superusers_idx_vigencia
  ON app_superusers (is_revoked, expires_at);
