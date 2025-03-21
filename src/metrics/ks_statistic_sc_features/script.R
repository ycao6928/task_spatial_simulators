requireNamespace("anndata", quietly = TRUE)
requireNamespace("edgeR", quietly = TRUE)
requireNamespace("ks", quietly = TRUE)
requireNamespace("resample", quietly = TRUE)
requireNamespace("reshape2", quietly = TRUE)
requireNamespace("scFeatures", quietly = TRUE)
requireNamespace("CARD", quietly = TRUE)
requireNamespace("SingleCellExperiment", quietly = TRUE)
requireNamespace("SummarizedExperiment", quietly = TRUE)


packages <- c(
  "SingleCellExperiment",
  "SummarizedExperiment",
  "concaveman",
  "sp",
  "Matrix",
  "methods",
  "ggplot2",
  "ggcorrplot",
  "MuSiC",
  "fields",
  "MCMCpack",
  "dplyr",
  "sf",
  "RANN",
  "stats",
  "reshape2",
  "RColorBrewer",
  "scatterpie",
  "grDevices",
  "nnls",
  "pbmcapply",
  "spatstat",
  "gtools",
  "RcppML",
  "NMF"
)

# Load each package
lapply(packages, library, character.only = TRUE)

## VIASH START
par <- list(
  input_spatial_dataset = "temp_brain.zinbwave.ks_statistic_sc_features/_viash_par/input_spatial_dataset_1/output_sp.h5ad",
  input_singlecell_dataset = "temp_brain.zinbwave.ks_statistic_sc_features/_viash_par/input_singlecell_dataset_1/output_sc.h5ad",
  input_simulated_dataset = "temp_brain.zinbwave.ks_statistic_sc_features/_viash_par/input_simulated_dataset_1/brain.zinbwave.generate_sim_spatialcluster.output_sp.h5ad",
  output = "output.h5ad"
)
meta <- list(
  name = "ks_statistic",
  resources_dir = "target/executable/metrics/ks_statistic_sc_features"
)
## VIASH END

source(paste0(meta[["resources_dir"]], "/utils.R"))

input_real_sp <- anndata::read_h5ad(par$input_spatial_dataset)
input_sc <- anndata::read_h5ad(par$input_singlecell_dataset)
input_simulated_sp <- anndata::read_h5ad(par$input_simulated_dataset)

real_log_count <- t(input_real_sp$layers[["logcounts"]])
real_prob_matrix <- input_real_sp$obsm[["celltype_proportions"]]
colnames(real_prob_matrix) <- paste0("ct", seq_len(ncol(real_prob_matrix)))

sim_log_count <- scuttle::normalizeCounts(t(input_simulated_sp$layers[[
  "counts"
]]))
real_log_count <- real_log_count[,
  colnames(real_log_count) %in% rownames(real_prob_matrix)
]


sim_sce <- scater::logNormCounts(SingleCellExperiment::SingleCellExperiment(
  list(counts = Matrix::t(input_simulated_sp$layers[["counts"]])),
  colData = input_simulated_sp$obs,
  metadata = input_simulated_sp$obsm
))

sim_log_count <- SummarizedExperiment::assay(sim_sce, "logcounts")

# helper function
try_kde_test <- function(x1, x2) {
  tryCatch(
    {
      ks::kde.test(x1 = x1, x2 = x2)
    },
    error = function(e) {
      warning(
        "Caught error in ks::kde.test: ",
        e$message,
        "\n\nTrying again with some random noise added to the vectors."
      )
      x1_noise <- stats::runif(length(x1), -1e-8, 1e-8)
      x2_noise <- stats::runif(length(x2), -1e-8, 1e-8)
      ks::kde.test(x1 = x1 + x1_noise, x2 = x2 + x2_noise)
    }
  )
}

# build cell type deconvolution in simulated data ## error
sim_prob_matrix <- CARD_processing(input_real_sp, input_sc)

sim_log_count <- sim_log_count[,
  colnames(sim_log_count) %in% rownames(sim_prob_matrix)
]

feat_types <- c("L_stats", "celltype_interaction", "nn_correlation", "morans_I")

real_scfeatures_result <- scFeatures::scFeatures(
  real_log_count,
  sample = rep("sample1", ncol(real_log_count)),
  spatialCoords = input_real_sp$obs[c("row", "col")],
  feature_types = feat_types,
  type = "spatial_t",
  species = sc_species,
  spotProbability = t(real_prob_matrix)
)

sim_scfeatures_result <- scFeatures::scFeatures(
  sim_log_count,
  sample = rep("sample1", ncol(sim_log_count)),
  spatialCoords = input_simulated_sp$obs[c("row", "col")],
  feature_types = feat_types,
  type = "spatial_t",
  species = sc_species,
  spotProbability = t(sim_prob_matrix)
)

ks_statistic_L_stats <- try_kde_test(
  x1 = as.numeric(real_scfeatures_result$L_stats),
  x2 = as.numeric(sim_scfeatures_result$L_stats)
)
ks_statistic_celltype_interaction <- try_kde_test(
  x1 = as.numeric(real_scfeatures_result$celltype_interaction),
  x2 = as.numeric(sim_scfeatures_result$celltype_interaction)
)
ks_statistic_nn_correlation <- try_kde_test(
  x1 = as.numeric(real_scfeatures_result$nn_correlation),
  x2 = as.numeric(sim_scfeatures_result$nn_correlation)
)
ks_statistic_morans_I <- try_kde_test(
  x1 = as.numeric(real_scfeatures_result$morans_I),
  x2 = as.numeric(sim_scfeatures_result$morans_I)
)

cat("Combining metric values\n")
uns_metric_ids <- c(
  "ks_statistic_L_stats",
  "ks_statistic_celltype_interaction",
  "ks_statistic_nn_correlation",
  "ks_statistic_morans_I"
)

uns_metric_values <- c(
  ks_statistic_L_stats$zstat,
  ks_statistic_celltype_interaction$zstat,
  ks_statistic_nn_correlation$zstat,
  ks_statistic_morans_I$zstat
)

cat("Writing output AnnData to file\n")
output <- anndata::AnnData(
  uns = list(
    dataset_id = input_simulated_sp$uns[["dataset_id"]],
    method_id = input_simulated_sp$uns[["method_id"]],
    metric_ids = uns_metric_ids,
    metric_values = uns_metric_values
  ),
  shape = c(0L, 0L)
)
output$write_h5ad(par[["output"]], compression = "gzip")
