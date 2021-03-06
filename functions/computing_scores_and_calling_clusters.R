
# David L Gibbs
# dgibbs@systemsbiology.org

# this script will form the backend of the shiny app.


# this function computes scores given some expression data.
newScores <- function(fileinfo, logflag, ensemblesize, combatflag, sepflag, normflag) {

  library(R.utils)
  library(data.table)

  zscore.cols2<-function(x){
    return((apply(x, 2, function(x) (x - median(na.omit(x)))/sd(na.omit(x)))))
  }

  print(fileinfo)
  print(logflag)
  print(ensemblesize)
  print(combatflag)
  print(sepflag)

  if(is.null(fileinfo)) {
    print("HERE")
    fileinfo <- list(name='ebpp_test1_1to20.tsv',  size=1, type='text/tsv', datapath='data/ebpp_test1_1to20.tsv')
  }

  print(fileinfo)

  load('data/comparative_immuneSigs_geneLists4.rda')

  # problem here is that when the file is gzipped
  # the fileinfo is not helpful in determing sep
  #if (fileinfo$type == 'text/csv') {
  #  s1 <- ','
  #} else if (fileinfo$type == 'text/tab-separated-values') {
  #  s1 <- '\t'
  #} else {
  #  s1 <- '\t'
  #}
  #``

  print("Reading Data")

  #newdata <- read_csv('data/ivy20.csv')
  newdata <- read.table(file=fileinfo$datapath, sep=sepflag, header=T, stringsAsFactors = F)
  #newdata <- read.table('~/Work/iAtlas/Immune-Subtype-Clustering/ExtraData/ebpp_test1_1to20.tsv', sep='\t', header=T, stringsAsFactors = F)

  print("new data")
  print(dim(newdata))

  # 1. the EBPP expression data subset
  reportedScores <- read.table('data/five_signature_mclust_ensemble_results.tsv.gz', sep='\t', header=T, stringsAsFactors = F)
  rownames(reportedScores) <- reportedScores$AliquotBarcode


  print("Loading TCGA Data")
  # 1. the EBPP expression data subset
  #tcgaSubset <- fread('data/ebppSubset.tsv.bz2', header = F)

  tcgaSubset1 <- fread('data/ebpp_subset_1.tsv.bz2')
  tcgaSubset2 <- fread('data/ebpp_subset_2.tsv.bz2')
  tcgaSubset3 <- fread('data/ebpp_subset_3.tsv.bz2')

  tcgaSubsetA <- cbind(tcgaSubset1, tcgaSubset2)
  tcgaSubset  <- cbind(tcgaSubsetA, tcgaSubset3)

  rm(tcgaSubset1, tcgaSubset2, tcgaSubset3, tcgaSubsetA)
  print(gc())


  tcgaGenes <- tcgaSubset$GeneID
  tcgaSubset <- log2(tcgaSubset[,-1] + 1)
  tcgaSubset <- cbind(data.frame(GeneID=tcgaGenes), tcgaSubset)

  # 2 we get some new data in.. require:
  #    it is RSEM
  #    and   log2 transformed
  #    and   gene symbols as row names
  #    and   median centered
  newdata <- as.data.frame(newdata)
  didx <- !duplicated(newdata[,1])
  dat <- newdata[didx,-1]
  rownames(dat) <- newdata[,1]

  # in the EB++ data, the 75% on values GREATER than 0 is 1000.

  if (normflag) {
    #data.quantileAll <- apply(dat, 2, function(x){quantile(x, 0.75)})
    data.quantileExpressed <- apply(dat, 2, function(x){quantile(x[x>0], 0.75)})
    datnorm <- as.data.frame(t( t(dat) / data.quantileExpressed ) ) * 1000
  } else {
    datnorm <- dat
  }

  if (logflag) {
    datlog2 <- log2(datnorm+1)
  } else {
    datlog2 <- datnorm
  }

  # medians of each gene
  #newDatMeds<- apply(datlog2, 1, median, na.rm=T)
  # center each gene
  #datlog2Centered <- sweep(datlog2,  1, newDatMeds, '-')
  # bring the genes back in
  #dat2 <- cbind(data.frame(GeneSymbol=rownames(dat)), datlog2Centered)

  ### joining data sets ###

  datlog2g <- cbind(data.frame(GeneID = newdata[,1]), datlog2)
  colnames(tcgaSubset)[1] <- colnames(datlog2g)[1]
  #joinDat <- inner_join(dat2, tcgaSubset)
  joinDat <- inner_join(datlog2g, tcgaSubset)
  joinGenes <- joinDat$GeneID

  # clean up
  newdatSamples <- colnames(datlog2g)
  dat2idx <- 1:(ncol(datlog2)-1)
  tcgaidx <- setdiff( (1: (ncol(joinDat)-1)), dat2idx)

  rm(tcgaSubset, datlog2, datlog2Centered, newdata, didx, newDatMeds)
  print(gc())
  gc()

  joinDat <- joinDat[,-1]
  rownames(joinDat) <- joinGenes
  print(gc())

  print("Making data subsets")

  sampleIdx <- c(dat2idx, sample(tcgaidx, size=200, replace = F))
  preCombat <- joinDat[,sampleIdx]
  preCombatMelt <- reshape2::melt(preCombat)
  preCombatMelt$SampleSource <- ifelse(test = preCombatMelt$variable %in% newdatSamples, yes = "New Data", no="TCGA Data")

  print("Combat")

  if (combatflag) {
    # then batch correction between scores...
    batch <- c(rep(1,length(dat2idx)), rep(2,length(tcgaidx)))
    modcombat = model.matrix(~1, data=as.data.frame(t(joinDat)))
    combat_edata = ComBat(dat=joinDat, batch=batch, mod=modcombat,
                          par.prior=TRUE, prior.plots=FALSE, ref.batch = 2)
  } else {
    combat_edata = joinDat
  }

  rm(modcombat, preCombat, joinDat)
  gc()

  print("Computing scores")
  postCombat <- combat_edata[,sampleIdx]
  postCombatMelt <- reshape2::melt(postCombat)
  postCombatMelt$SampleSource <- ifelse(test = postCombatMelt$variable %in% newdatSamples, yes = "New Data", no="TCGA Data")

  ### median center
  joinMeds<- apply(combat_edata, 1, median, na.rm=T)
  # center each gene
  joinCentered <- sweep(combat_edata,  1, joinMeds, '-')
  rownames(joinCentered) <- joinGenes

  ### compute scores.
  datScores <- ImmuneSigs_function(joinCentered,
                                   sigs1_2_eg2,sigs12_weighted_means,
                                   sigs12_module_weights,sigs1_2_names2,sigs1_2_type2,
                                   2)

  gc()

  print("Calling subtypes")

  # and we subset the 5 scores used in clustering
  idx <- c("LIexpression_score", "CSF1_response", "TGFB_score_21050467", "Module3_IFN_score", "CHANG_CORE_SERUM_RESPONSE_UP")
  scores <- t(datScores[idx,])
  zscores <- zscore.cols2(scores)

  # load the clustering model trained on all pancan data.
  #incProgress()
  load("data/wolf_set_slim1.rda")

  # make cluster calls using the models.
  calls <- consensusEnsemble(mods2, zscores, 2, ensemblesize)

  print("Reporting clusters")

  # get the top scoring cluster for each sample
  maxcalls <- apply(calls$.Data, 1, function(a) which(a == max(a))[1])
  names(maxcalls) <- rownames(scores)

  # then we'll look at the new vs. old cluster calls for TCGA samples
  sharedIDs <- intersect(reportedScores$AliquotBarcode, rownames(scores))
  t1 <-table(Reported=as.numeric(reportedScores[sharedIDs, 'ClusterModel1']),
             NewCalls=as.numeric(maxcalls[sharedIDs]))

  # then we can align the new calls to old calls.
  reported <- 1:6
  optcalls <- 1:6
  otherway <- 1:6
  for (i in reported) {

    # for subtype i, where did most of the samples end up?
    j <- which(as.numeric(t1[i,]) == max(as.numeric(t1[i,])))
    # rename maxcall j <- i
    optcalls[i] <- j
    otherway[j] <- i
  }

  print(optcalls)
  print(otherway)

  # these are the re-mapped calls
  alignedCalls <- sapply(maxcalls, function(a) which(a == optcalls)[1])

  # make sure it works
  t2 <-table(Reported=as.numeric(reportedScores[sharedIDs, 'ClusterModel1']),
             NewCalls=as.numeric(alignedCalls[sharedIDs]))

  # assemble the results
  jdx <- match(table=rownames(scores), x=colnames(dat))  # index to new data scores
  pcalls <- calls$.Data[jdx,]                            # get that table
  rownames(pcalls) <- colnames(dat)                     # name it from the new data
  pcalls <- pcalls[,optcalls]

  pcalls <- cbind(pcalls, data.frame(Call=alignedCalls[jdx]))  # bring in the aligned calls
  pcalls <- cbind(pcalls, zscores[jdx,])                       # and the scores


  devtools::unload(package = 'R.utils')
  print("Done")

  return(list(AlignedCalls=alignedCalls[jdx], Table=t2, ProbCalls=pcalls, PreCombat=preCombatMelt, PostCombat=postCombatMelt))

}


