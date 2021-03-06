library(data.table)
library(assertthat)
library(ggplot2)
library(scales)
library(cowplot)

args <- commandArgs(trailingOnly = T)
f_in <- args[1]
f_svs <- args[2]
f_seg <- args[3]
my_k  <- as.integer(args[4])
windowsize <- as.integer(args[5])
pdf_out <- args[6]


format_Mb <- function(x) {
    paste(comma(x/1e6), "Mb")
}

# if gzip
if (substr(f_in,nchar(f_in)-2,nchar(f_in)) == ".gz")
    f_in = paste("zcat",f_in)

# Read counts & filter chromosomes (this is human-specific)
d = fread(f_in)

# Check that correct files are given:
assert_that("chrom" %in% colnames(d))
assert_that("start" %in% colnames(d) && is.integer(d$start))
assert_that("end" %in% colnames(d) && is.integer(d$end))
assert_that("sample" %in% colnames(d))
assert_that("cell" %in% colnames(d))
assert_that("w" %in% colnames(d) && is.integer(d$w))
assert_that("c" %in% colnames(d) && is.integer(d$c))
assert_that("class" %in% colnames(d))

# Re-name and -order chromosomes
d = d[, chrom := sub('^chr','',chrom)][]
d = d[grepl('^([1-9]|[12][0-9]|X|Y)$', chrom),]
d = d[, chrom := factor(chrom, levels=as.character(c(1:22,'X','Y')), ordered = T)]


# Read SV file
sv = fread(f_svs)
colnames(sv) = c("chrom","start","end","type","vaf")
sv = sv[, chrom := sub('^chr','',chrom)][]

# Read segments
seg = fread(f_seg)
colnames(seg) = c("k","bin","chrom")
seg = seg[, chrom := sub('^chr','',chrom)][]
# Choose 75% median k for each chromosome
seg = seg[,.SD[k == as.integer(max(k)*0.75),], by = chrom]
seg$pos = seg$bin * windowsize





# Plot all cells
cairo_pdf(pdf_out, width=14, height=10, onefile = T)
for (s in unique(d$sample))
{
    for (ce in unique(d[sample == s,]$cell))
    {
        message(paste("Plotting sample", s, "cell", ce,"into",pdf_out))
        
        e = d[sample == s & cell == ce,]
        
        # Calculate some information
        info_binwidth = median(e$end - e$start)
        info_reads_per_bin = median(e$w + e$c)
        info_chrom_sizes = e[, .(xend = max(end)), by = chrom]
        info_num_bins = nrow(e)
        info_total_reads = sum(e$c + e$w)
        info_y_limit = 2*info_reads_per_bin+1
        info_sample_name = substr(s,1,25)
        if (nchar(s)>25) info_sample_name = paste0(info_sample_name, "...")
        info_cell_name   = substr(ce,1,25)
        if (nchar(ce)>25) info_cell_name = paste0(info_cell_name, "...")
        
        # start main plot:
        plt <- ggplot(e) +
            aes(x = (start+end)/2)
        
        
        # prepare consecutive rectangles for a better plotting experience
        consecutive = cumsum(c(0,abs(diff(as.numeric(as.factor(e$class))))))
        e$consecutive = consecutive
        f = e[, .(start = min(start), end = max(end), class = class[1]), by = .(consecutive, chrom)][]

        
        plt <- plt +
            geom_rect(data = f, aes(xmin = start, xmax=end, ymin=-Inf, ymax=Inf, fill=class), inherit.aes=F, alpha=0.2) +
            scale_fill_manual(values = c(WW = "sandybrown", CC = "paleturquoise4", WC = "yellow", None = NA))
        
        if (nrow(sv) > 0) plt <- plt +
            geom_rect(data = sv, aes(xmin = start, xmax = end, ymin = -Inf, ymax = Inf), fill = "dodgerblue2", alpha = 0.3)
       
        plt <- plt + 
            geom_vline(data = seg, aes(xintercept = pos), col = "black", size = 0.1)
    

        # Watson/Crick bars
        plt <- plt +
            geom_bar(aes(y = -w, width=(end-start)), stat='identity', position = 'identity', fill='sandybrown') +
            geom_bar(aes(y = c, width=(end-start)), stat='identity', position = 'identity', fill='paleturquoise4') +
            # Trim image to 2*median cov
            coord_flip(expand = F, ylim=c(-info_y_limit, info_y_limit)) +
            facet_grid(.~chrom, switch="x") +
            ylab("Watson | Crick") + xlab(NULL) +
            scale_x_continuous(breaks = pretty_breaks(12), labels = format_Mb) +
            scale_y_continuous(breaks = pretty_breaks(3)) + 
            theme_classic() +
            theme(panel.margin = unit(0, "lines"),
                  axis.text.x = element_blank(),
                  axis.ticks.x = element_blank(),
                  strip.background = element_rect(fill = NA, colour=NA)) + 
            guides(fill = FALSE) +
            # Dotted lines at median bin count
            geom_segment(data = info_chrom_sizes, aes(xend = xend, x=0, y=-info_reads_per_bin, yend=-info_reads_per_bin),
                         linetype="dotted", col="darkgrey", size=0.5) +
            geom_segment(data = info_chrom_sizes, aes(xend = xend, x=0, y=+info_reads_per_bin, yend=+info_reads_per_bin),
                         linetype="dotted", col="darkgrey", size=0.5) +
            geom_segment(data = info_chrom_sizes, aes(xend = xend, x=0), y=0, yend=0, size=0.5)
 
        print(plt)
        break
    }
}
dev.off()
