# var_funciones.R -------------------------------------------------------
# Funciones propias para VAR reducido, identificación recursiva (Cholesky),
# IRF con bandas bootstrap, FEVD, diagnósticos, BVAR Minnesota (observaciones
# ficticias, Banbura-Giannone-Reichlin 2010) y proyecciones locales.
# Están escritas en R base a propósito: cada paso queda a la vista para el
# revisor y no dependen de paquetes que cambien entre versiones.
#
# Convención: Y es una matriz T x N (columnas con nombre). Las tasas están en %,
# así que un choque de 25 pb es 0.25. Las variables en log están ×100.

# --- Construcción de rezagos ----------------------------------------------
var_matrices <- function(Y, p) {
  Y <- as.matrix(Y); TT <- nrow(Y); N <- ncol(Y)
  X <- matrix(1, TT - p, 1 + N * p)
  for (l in 1:p) X[, 1 + (l - 1) * N + 1:N] <- Y[(p - l + 1):(TT - l), ]
  colnames(X) <- c("const", paste0(rep(colnames(Y), p), "_L", rep(1:p, each = N)))
  list(Y = Y[(p + 1):TT, , drop = FALSE], X = X, N = N, p = p)
}

# --- Estimación MCO ------------------------------------------------------
var_ols <- function(Y, p) {
  m <- var_matrices(Y, p)
  XtXi <- solve(crossprod(m$X))
  B <- XtXi %*% crossprod(m$X, m$Y)              # (1+Np) x N
  U <- m$Y - m$X %*% B
  TT <- nrow(m$Y); K <- ncol(m$X)
  Sigma <- crossprod(U) / (TT - K)
  structure(list(B = B, U = U, Sigma = Sigma, Sigma_ml = crossprod(U) / TT,
                 X = m$X, Yd = m$Y, Y = as.matrix(Y), N = m$N, p = p, TT = TT, K = K,
                 nombres = colnames(Y)), class = "mivar")
}

# Matriz compañera (Np x Np)
companera <- function(B, N, p) {
  A <- t(B[-1, , drop = FALSE])                  # N x Np
  if (p == 1) return(A)
  rbind(A, cbind(diag(N * (p - 1)), matrix(0, N * (p - 1), N)))
}

raices <- function(v) sort(Mod(eigen(companera(v$B, v$N, v$p), only.values = TRUE)$values), decreasing = TRUE)

# --- Selección de rezagos (muestra común) ----------------------------------
seleccion_rezagos <- function(Y, pmax = 13) {
  Y <- as.matrix(Y); N <- ncol(Y)
  out <- lapply(1:pmax, function(p) {
    Yp <- Y[(pmax - p + 1):nrow(Y), , drop = FALSE]   # misma muestra efectiva para todos
    v <- var_ols(Yp, p)
    ld <- as.numeric(determinant(v$Sigma_ml)$modulus)
    k <- N * v$K; TT <- v$TT
    data.frame(p = p, AIC = ld + 2 * k / TT, BIC = ld + log(TT) * k / TT,
               HQ = ld + 2 * log(log(TT)) * k / TT)
  })
  do.call(rbind, out)
}

# --- Medias móviles (respuestas a innovaciones reducidas) ------------------
ma_coef <- function(B, N, p, H) {
  A <- companera(B, N, p)
  Phi <- array(0, c(N, N, H + 1)); Phi[, , 1] <- diag(N)
  Ak <- diag(N * p)
  for (h in 1:H) { Ak <- Ak %*% A; Phi[, , h + 1] <- Ak[1:N, 1:N] }
  Phi
}

# IRF Cholesky de todas las variables a un choque en `choque`, escalado para que
# la respuesta de impacto de `choque` sea `escala` (p. ej., 0.25 = +25 pb).
irf_chol <- function(B, Sigma, N, p, H, choque, escala = NULL) {
  P <- t(chol(Sigma))
  Phi <- ma_coef(B, N, p, H)
  j <- choque
  r <- t(sapply(1:(H + 1), function(h) Phi[, , h] %*% P[, j]))
  if (!is.null(escala)) r <- r * escala / P[j, j]
  r                                                # (H+1) x N
}

# --- Bootstrap de residuos (diseño recursivo) -------------------------------
simular_var <- function(B, U, Y0, TT, N, p) {
  Ys <- matrix(0, TT + p, N); Ys[1:p, ] <- Y0
  idx <- sample.int(nrow(U), TT, replace = TRUE)
  A <- B[-1, , drop = FALSE]; c0 <- B[1, ]
  for (t in 1:TT) {
    x <- as.vector(t(Ys[(t + p - 1):t, , drop = FALSE]))   # [y_{t-1}', ..., y_{t-p}']
    Ys[t + p, ] <- c0 + x %*% A + U[idx[t], ]
  }
  Ys
}

irf_bootstrap <- function(v, H = 48, choque, escala = 0.25, nboot = 1000, semilla = 123) {
  set.seed(semilla)
  base <- irf_chol(v$B, v$Sigma, v$N, v$p, H, choque, escala)
  Uc <- scale(v$U, center = TRUE, scale = FALSE)
  Y0 <- v$Y[1:v$p, , drop = FALSE]
  draws <- array(NA_real_, c(H + 1, v$N, nboot))
  for (b in 1:nboot) {
    Ys <- simular_var(v$B, Uc, Y0, v$TT, v$N, v$p)
    colnames(Ys) <- v$nombres
    vb <- var_ols(Ys, v$p)
    if (max(raices(vb)) >= 1.05) next              # descarta réplicas explosivas
    draws[, , b] <- irf_chol(vb$B, vb$Sigma, v$N, v$p, H, choque, escala)
  }
  ok <- !is.na(draws[1, 1, ])
  dimnames(draws) <- list(NULL, v$nombres, NULL)
  colnames(base) <- v$nombres
  list(base = base, draws = draws[, , ok, drop = FALSE], H = H, nboot_ok = sum(ok))
}

# Tabla larga de IRF con bandas 68% y 90% (opcional: combinaciones lineales)
irf_tabla <- function(ib, combos = list()) {
  base <- ib$base; dr <- ib$draws
  for (nm in names(combos)) {
    w <- combos[[nm]]                                # vector con nombres de columnas
    base <- cbind(base, base[, names(w)] %*% w); colnames(base)[ncol(base)] <- nm
    add <- apply(dr[, names(w), , drop = FALSE], c(1, 3), function(z) sum(z * w))
    dr <- abind2(dr, add, nm)
  }
  out <- lapply(colnames(base), function(k) {
    q <- apply(dr[, k, , drop = FALSE], 1, quantile, probs = c(.05, .16, .5, .84, .95), na.rm = TRUE)
    data.frame(h = 0:ib$H, variable = k, irf = base[, k],
               q05 = q[1, ], q16 = q[2, ], q50 = q[3, ], q84 = q[4, ], q95 = q[5, ])
  })
  do.call(rbind, out)
}
abind2 <- function(dr, add, nm) {
  out <- array(NA_real_, dim(dr) + c(0, 1, 0))
  out[, 1:dim(dr)[2], ] <- dr; out[, dim(dr)[2] + 1, ] <- add
  dimnames(out) <- list(NULL, c(dimnames(dr)[[2]], nm), NULL); out
}

# --- FEVD ----------------------------------------------------------------
fevd_chol <- function(v, horizontes = c(12, 24, 48)) {
  H <- max(horizontes); P <- t(chol(v$Sigma))
  Phi <- ma_coef(v$B, v$N, v$p, H)
  Theta <- array(0, c(v$N, v$N, H + 1))
  for (h in 1:(H + 1)) Theta[, , h] <- Phi[, , h] %*% P
  out <- lapply(horizontes, function(hh) {
    num <- apply(Theta[, , 1:hh, drop = FALSE]^2, c(1, 2), sum)   # var i, choque j
    sh <- num / rowSums(num)
    data.frame(horizonte = hh, variable = v$nombres, sh, check.names = FALSE)
  })
  out <- do.call(rbind, out)
  names(out)[-(1:2)] <- paste0("choque_", v$nombres)
  out
}

# Choques estructurales (Cholesky): e_t = P^{-1} u_t
choques_estructurales <- function(v) {
  P <- t(chol(v$Sigma)); E <- t(solve(P, t(v$U))); colnames(E) <- v$nombres; E
}

# --- Diagnósticos --------------------------------------------------------
# Portmanteau multivariado ajustado (Lütkepohl 2005, ec. 4.4.23)
portmanteau <- function(v, h = 24) {
  U <- scale(v$U, scale = FALSE); TT <- nrow(U); N <- v$N
  C0i <- solve(crossprod(U) / TT); Q <- 0
  for (j in 1:h) {
    Cj <- crossprod(U[(j + 1):TT, ], U[1:(TT - j), ]) / TT
    Q <- Q + sum(diag(t(Cj) %*% C0i %*% Cj %*% C0i)) / (TT - j)
  }
  Q <- TT^2 * Q; df <- N^2 * (h - v$p)
  data.frame(test = paste0("Portmanteau ajustado (h=", h, ")"), estadistico = Q, gl = df,
             p_valor = pchisq(Q, df, lower.tail = FALSE))
}
# LM de correlación serial (Breusch-Godfrey multivariado, versión F de Rao/Edgerton-Shukur)
lm_serial <- function(v, h = 12) {
  U <- v$U; TT <- nrow(U); N <- v$N
  Ul <- matrix(0, TT, N * h)
  for (j in 1:h) Ul[(j + 1):TT, (j - 1) * N + 1:N] <- U[1:(TT - j), ]
  Z <- cbind(v$X, Ul)
  Ue <- U - Z %*% qr.solve(Z, U)
  Su <- crossprod(U) / TT; Se <- crossprod(Ue) / TT
  r2 <- 1 - sum(diag(solve(Su, Se))) / N
  LM <- TT * (N - sum(diag(solve(Su, Se))))
  df <- h * N^2
  data.frame(test = paste0("LM correlación serial (h=", h, ")"), estadistico = LM, gl = df,
             p_valor = pchisq(LM, df, lower.tail = FALSE))
}
diag_ecuaciones <- function(v, lags_arch = 12) {
  do.call(rbind, lapply(1:v$N, function(i) {
    u <- v$U[, i]
    jb <- tseries::jarque.bera.test(u)
    u2 <- u^2; n <- length(u2)
    Z <- embed(u2, lags_arch + 1)
    a <- summary(lm(Z[, 1] ~ Z[, -1]))
    archLM <- nrow(Z) * a$r.squared
    data.frame(ecuacion = v$nombres[i],
               JB = unname(jb$statistic), JB_p = jb$p.value,
               ARCH_LM = archLM, ARCH_p = pchisq(archLM, lags_arch, lower.tail = FALSE))
  }))
}

# --- BVAR Minnesota con observaciones ficticias -----------------------------
# Banbura, Giannone y Reichlin (2010): prior de camino aleatorio (delta = 1)
# con tensión general lambda; constante difusa. Posterior Normal-Wishart inversa.
bvar_dummies <- function(Y, p, lambda, delta = 1, eps = 1e-3) {   # eps: precisión (difusa) de la constante
  Y <- as.matrix(Y); N <- ncol(Y)
  sig <- apply(Y, 2, function(y) { a <- ar.ols(y, order.max = 1, aic = FALSE, demean = TRUE); sqrt(a$var.pred) })
  delta <- rep(delta, length.out = N)
  K <- 1 + N * p
  Yd <- rbind(diag(delta * sig) / lambda,
              matrix(0, N * (p - 1), N),
              diag(sig),
              matrix(0, 1, N))
  Xd <- rbind(cbind(0, kronecker(diag(1:p), diag(sig) / lambda)),
              matrix(0, N, K),
              c(eps, rep(0, N * p)))
  list(Yd = Yd, Xd = Xd)
}
logml_niw <- function(Ys, Xs) {
  # log de la parte de la verosimilitud marginal que depende de los datos (sin π)
  TT <- nrow(Ys); K <- ncol(Xs); N <- ncol(Ys)
  XtX <- crossprod(Xs); B <- solve(XtX, crossprod(Xs, Ys)); S <- crossprod(Ys - Xs %*% B)
  lmvg <- function(a) N * (N - 1) / 4 * log(pi) + sum(lgamma(a + (1 - 1:N) / 2))
  -N / 2 * as.numeric(determinant(XtX)$modulus) -
    (TT - K) / 2 * as.numeric(determinant(S)$modulus) + lmvg((TT - K) / 2)
}
bvar_fit <- function(Y, p, lambda) {
  m <- var_matrices(Y, p); d <- bvar_dummies(Y, p, lambda)
  Ys <- rbind(m$Y, d$Yd); Xs <- rbind(m$X, d$Xd)
  lml <- logml_niw(Ys, Xs) - logml_niw(d$Yd, d$Xd) - nrow(m$Y) * m$N / 2 * log(pi)
  XtXi <- solve(crossprod(Xs)); B <- XtXi %*% crossprod(Xs, Ys)
  S <- crossprod(Ys - Xs %*% B)
  list(B = B, S = S, XtXi = XtXi, df = nrow(Ys) - ncol(Xs), lml = lml, N = m$N, p = p,
       lambda = lambda, nombres = colnames(Y))
}
bvar_lambda <- function(Y, p, grilla = seq(0.05, 1, by = 0.05)) {
  data.frame(lambda = grilla, logML = sapply(grilla, function(l) bvar_fit(Y, p, l)$lml))
}
rinvwishart <- function(S, df) { W <- rWishart(1, df, solve(S))[, , 1]; solve(W) }
bvar_irf <- function(fit, H = 48, choque, escala = 0.25, ndraws = 1000, semilla = 321) {
  set.seed(semilla); N <- fit$N; K <- nrow(fit$B)
  cXi <- chol(fit$XtXi)
  draws <- array(NA_real_, c(H + 1, N, ndraws))
  for (d in 1:ndraws) {
    Sig <- rinvwishart(fit$S, fit$df)
    Z <- matrix(rnorm(K * N), K, N)
    Bd <- fit$B + t(cXi) %*% Z %*% chol(Sig)
    if (max(Mod(eigen(companera(Bd, N, fit$p), only.values = TRUE)$values)) >= 1.05) next
    draws[, , d] <- irf_chol(Bd, Sig, N, fit$p, H, choque, escala)
  }
  ok <- !is.na(draws[1, 1, ])
  Sig_m <- fit$S / (fit$df - N - 1)
  base <- irf_chol(fit$B, Sig_m, N, fit$p, H, choque, escala); colnames(base) <- fit$nombres
  dr <- draws[, , ok, drop = FALSE]; dimnames(dr) <- list(NULL, fit$nombres, NULL)
  list(base = base, draws = dr, H = H, nboot_ok = sum(ok))
}

# --- Proyecciones locales con choques positivos y negativos -----------------
# y_{t+h} - y_{t-1} = a_h + b+_h e+_t + b-_h e-_t + controles_t + u ; Newey-West con h+1 rezagos
lp_asimetrica <- function(y, e, controles, H = 36) {
  ep <- pmax(e, 0); en <- pmin(e, 0); TT <- length(y)
  do.call(rbind, lapply(0:H, function(h) {
    idx <- 2:(TT - h)
    dy <- y[idx + h] - y[idx - 1]
    df <- data.frame(dy = dy, ep = ep[idx], en = en[idx], controles[idx, , drop = FALSE])
    m <- lm(dy ~ ., data = df)
    V <- sandwich::NeweyWest(m, lag = h + 1, prewhite = FALSE)
    b <- coef(m)[c("ep", "en")]; s <- sqrt(diag(V)[c("ep", "en")])
    # H0: b+ = b- (efecto simétrico: subir 1 y bajar 1 dan respuestas espejo)
    dif <- b[1] - b[2]; sd_dif <- sqrt(V["ep", "ep"] + V["en", "en"] - 2 * V["ep", "en"])
    data.frame(h = h, b_pos = b[1], se_pos = s[1], b_neg = b[2], se_neg = s[2],
               t_igualdad = dif / sd_dif, p_igualdad = 2 * pnorm(-abs(dif / sd_dif)), n = nrow(df))
  }))
}

# Matriz de controles: p rezagos de un conjunto de variables
rezagos_df <- function(Y, p) {
  Y <- as.matrix(Y); TT <- nrow(Y)
  out <- do.call(cbind, lapply(1:p, function(l) rbind(matrix(NA, l, ncol(Y)), Y[1:(TT - l), , drop = FALSE])))
  colnames(out) <- paste0(rep(colnames(Y), p), "_L", rep(1:p, each = ncol(Y)))
  as.data.frame(out)
}

# --- SVAR con instrumento externo (proxy SVAR) ------------------------------
# Stock y Watson (2012), Mertens y Ravn (2013), Gertler y Karadi (2015).
# El vector de impacto del choque de política es proporcional a cov(u, z), donde u
# son los residuos reducidos y z la sorpresa de mercado. Se normaliza para que la
# variable de política suba `escala` en el impacto.
proxy_impacto <- function(U, z, j, escala = 0.25) {
  ok <- !is.na(z)
  s <- as.vector(crossprod(U[ok, , drop = FALSE], z[ok]))   # ∝ cov(u, z)
  s * escala / s[j]
}
primera_etapa <- function(U, z, j) {
  ok <- !is.na(z)
  m <- lm(U[ok, j] ~ z[ok])
  V <- sandwich::vcovHC(m, type = "HC1")
  tt <- coef(m)[2] / sqrt(V[2, 2])
  data.frame(n = sum(ok), coef = unname(coef(m)[2]), F_robusto = unname(tt^2),
             R2 = summary(m)$r.squared)
}
irf_desde_impacto <- function(B, N, p, H, s) {
  Phi <- ma_coef(B, N, p, H)
  t(sapply(1:(H + 1), function(h) Phi[, , h] %*% s))
}
# Wild bootstrap recursivo: residuos y sorpresa se multiplican por el mismo ±1 (Rademacher)
proxy_bootstrap <- function(v, z, j, H = 48, escala = 0.25, nboot = 500, semilla = 99) {
  set.seed(semilla)
  s0 <- proxy_impacto(v$U, z, j, escala)
  base <- irf_desde_impacto(v$B, v$N, v$p, H, s0); colnames(base) <- v$nombres
  Uc <- v$U; Y0 <- v$Y[1:v$p, , drop = FALSE]
  A <- v$B[-1, , drop = FALSE]; c0 <- v$B[1, ]
  draws <- array(NA_real_, c(H + 1, v$N, nboot))
  for (b in 1:nboot) {
    w <- sample(c(-1, 1), v$TT, replace = TRUE)
    Ub <- Uc * w; zb <- z * w
    Ys <- matrix(0, v$TT + v$p, v$N); Ys[1:v$p, ] <- Y0
    for (t in 1:v$TT) {
      x <- as.vector(t(Ys[(t + v$p - 1):t, , drop = FALSE]))
      Ys[t + v$p, ] <- c0 + x %*% A + Ub[t, ]
    }
    colnames(Ys) <- v$nombres
    vb <- var_ols(Ys, v$p)
    if (max(raices(vb)) >= 1.05) next
    sb <- proxy_impacto(vb$U, zb, j, escala)
    if (!all(is.finite(sb)) || max(abs(sb)) > 50 * escala) next   # instrumento casi nulo en la réplica
    draws[, , b] <- irf_desde_impacto(vb$B, v$N, v$p, H, sb)
  }
  ok <- !is.na(draws[1, 1, ])
  dr <- draws[, , ok, drop = FALSE]; dimnames(dr) <- list(NULL, v$nombres, NULL)
  list(base = base, draws = dr, H = H, nboot_ok = sum(ok), impacto = setNames(s0, v$nombres))
}
