version 1.0
import "convert_to_fasta.wdl" as convert_to_fasta

workflow CallAssemblyVariants {
    input {
        String assembly_name
        File contigs1
        File contigs2
        File ref
        File ref_index
        String ref_name
    }

    call align_contigs as align_contig1_to_ref {
        input:
            contigs=contigs1,
            ref=ref
    }

    call align_contigs as align_contig2_to_ref {
        input:
            contigs=contigs2,
            ref=ref
    }

    call align_contigs as align_contigs_to_each_other {
        input:
            contigs=contigs1,
            ref=contigs2
    }

    call index_fasta as index_contigs2 {
        input:
            fasta=contigs2
    }

    call call_small_variants as call_small_variants1_ref {
        input:
            alignment=align_contig1_to_ref.bam,
            ref=ref,
            ref_index=ref_index,
            assembly_name=assembly_name
    }

    call call_small_variants as call_small_variants2_ref {
        input:
            alignment=align_contig2_to_ref.bam,
            ref=ref,
            ref_index=ref_index,
            assembly_name=assembly_name
    }

    call call_small_variants as call_small_variants_self {
        input:
            alignment=align_contigs_to_each_other.bam,
            ref=index_contigs2.bgzipped_fasta,
            ref_index=index_contigs2.fasta_index,
            assembly_name=assembly_name
    }

    call call_sv as call_sv1_ref {
        input:
            alignment=align_contig1_to_ref.bam,
            contigs=contigs1,
            ref=ref,
            ref_index=ref_index,
            assembly_name=assembly_name
    }

    call call_sv as call_sv2_ref {
        input:
            alignment=align_contig2_to_ref.bam,
            contigs=contigs2,
            ref=ref,
            ref_index=ref_index,
            assembly_name=assembly_name
    }

    call call_sv as call_sv_self {
        input:
            alignment=align_contigs_to_each_other.bam,
            contigs=contigs1,
            ref=index_contigs2.bgzipped_fasta,
            ref_index=index_contigs2.fasta_index,
            assembly_name=assembly_name
    }

    call convert_to_fasta.ConvertToFasta as convert_ref1 {
        input:
            vcf=call_small_variants1_ref.vcf,
            vcf_index=call_small_variants1_ref.vcf_index,
            query=contigs1,
            ref=ref,
            ref_name=ref_name
    }

    call convert_to_fasta.ConvertToFasta as convert_ref2 {
        input:
            vcf=call_small_variants2_ref.vcf,
            vcf_index=call_small_variants2_ref.vcf_index,
            query=contigs2,
            ref=ref,
            ref_name=ref_name,
    }

    call convert_to_fasta.ConvertToFasta as convert_self {
        input:
            vcf=call_small_variants_self.vcf,
            vcf_index=call_small_variants_self.vcf_index,
            query=contigs1,
            ref=contigs2,
            ref_name=assembly_name
    }

    call combine_small_variants {
        input:
            small_variants1_ref = convert_ref1.marker_fasta,
            small_variants2_ref = convert_ref2.marker_fasta,
            small_variants_self = convert_self.marker_fasta,
            small_variants1_ref_marker_positions = convert_ref1.marker_positions,
            small_variants2_ref_marker_positions = convert_ref2.marker_positions,
            small_variants_self_marker_positions = convert_self.marker_positions,
            contigs1 = contigs1,
            contigs2 = contigs2,
            ref = ref
    }

    #call combine_sv {
    #    input:
    #        sv_ref1 = call_sv1_ref.bedpe,
    #        sv_ref2 = call_sv2_ref.bedpe,
    #        sv_self = call_sv_self.bedpe,
    #        contigs1 = contigs1,
    #        contigs2 = contigs2,
    #        ref = ref
    #}

    output {
        File small_variants = combine_small_variants.fasta
        File small_variants_marker_positions = combine_small_variants.marker_positions
    #   File sv = combine_sv.fasta
    }
}

task index_fasta {
    input {
        File fasta
    }
    command <<<
        set -exo pipefail
        BGZIP=/opt/hall-lab/htslib-1.9/bin/bgzip
        SAMTOOLS=/opt/hall-lab/samtools-1.9/bin/samtools
        zcat ~{fasta} | $BGZIP -c > bgzipped.fa.gz
        $SAMTOOLS faidx bgzipped.fa.gz
    >>>
    runtime {
        memory: "4G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File bgzipped_fasta = "bgzipped.fa.gz"
        File fasta_index = "bgzipped.fa.gz.fai"
    }
}

task combine_sv {
    input {
        File sv_ref1
        File sv_ref2
        File sv_self
        File contigs1
        File contigs2
        File ref
    }
    command <<<
    #TODO
    >>>
    runtime {
        memory: "64G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File fasta = "sv.combined.fasta"
    }
}

task combine_small_variants {
    input {
        File small_variants1_ref
        File small_variants2_ref
        File small_variants_self
        File small_variants1_ref_marker_positions
        File small_variants2_ref_marker_positions
        File small_variants_self_marker_positions
        File contigs1
        File contigs2
        File ref
    }
    command <<<
        set -exo pipefail
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        FIND_DUPS=/storage1/fs1/ccdg/Active/analysis/ref_grant/assembly_analysis_20200220/multiple_competitive_alignment/find_duplicate_markers.py #TODO
        #combine fasta files and sort by sequence
        cat ~{small_variants1_ref} ~{small_variants2_ref} ~{small_variants_self} | paste - - - - | awk -v OFS="\t" -v FS="\t" '{print($2, $4, $1, $3)}' | sort | awk -v OFS="\n" -v FS="\t" '{print($3,$1,$4,$2)}' > tmp
        #find duplicate markers
        $PYTHON $FIND_DUPS -i tmp > small_variants.combined.fasta
        cat ~{small_variants1_ref_marker_positions} ~{small_variants2_ref_marker_positions} ~{small_variants_self_marker_positions} | sort -u > small_variants.marker_positions.txt
    >>>
    runtime {
        memory: "64G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File fasta = "small_variants.combined.fasta"
        File marker_positions = "small_variants.marker_positions.txt"
    }
}

task call_sv {
    input {
        File alignment
        File contigs
        File ref
        File ref_index
        String assembly_name
    }
    command <<<
        set -exo pipefail
        SAMTOOLS=/opt/hall-lab/samtools-1.9/bin/samtools
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        SPLIT_TO_BEDPE=/opt/hall-lab/scripts/splitReadSamToBedpe
        BEDPE_TO_BKPTS=/opt/hall-lab/scripts/splitterToBreakpoint
        SVTOOLS=/opt/hall-lab/python-2.7.15/bin/svtools
        PERL=/usr/bin/perl
        REARRANGE_BREAKPOINTS=/opt/hall-lab/scripts/rearrange_breakpoints.pl
        GREP=/bin/grep
        ADD_ALIGNMENT_GAP_INFO=/opt/hall-lab/scripts/add_alignment_gap_info.pl

        $SAMTOOLS sort -n -T tmp -O bam ~{alignment} > namesorted.bam
        $SAMTOOLS view -h -F 4 namesorted.bam | $PYTHON $SPLIT_TO_BEDPE -i stdin > split.bedpe
        $PYTHON $BEDPE_TO_BKPTS -i split.bedpe -f ~{assembly_name} -q ~{contigs} -e ~{ref} > breakpoints.bedpe
        $SVTOOLS bedpesort breakpoints.bedpe | $PERL $REARRANGE_BREAKPOINTS > breakpoints.sorted.bedpe
        cat <($GREP "^#" breakpoints.sorted.bedpe) <(paste <($GREP -v "^#" breakpoints.sorted.bedpe | cut -f 1-6) <(paste -d : <($GREP -v "^#" breakpoints.sorted.bedpe | cut -f 7) <($GREP -v "^#" breakpoints.sorted.bedpe | cut -f 19 | sed 's/.*SVLEN=/SVLEN=/' | sed 's/;.*//')) <($GREP -v "^#" breakpoints.sorted.bedpe | cut -f 8-)) | $PERL $ADD_ALIGNMENT_GAP_INFO > breakpoints.sorted.fixed.bedpe
    mv breakpoints.sorted.fixed.bedpe breakpoints.sorted.bedpe
    >>>
    runtime {
        memory: "64G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File bedpe = "breakpoints.sorted.bedpe"
    }
}

task call_small_variants {
    input {
        File alignment
        File ref
        File ref_index
        String assembly_name
    }
    command <<<
        set -exo pipefail
        SAMTOOLS=/opt/hall-lab/samtools-1.9/bin/samtools
        PAFTOOLS=/opt/hall-lab/minimap2/misc/paftools.js
        K8=/opt/hall-lab/minimap2/k8
        BGZIP=/opt/hall-lab/htslib-1.9/bin/bgzip
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        VAR_TO_VCF=/opt/hall-lab/scripts/varToVcf.py
        SVTOOLS=/opt/hall-lab/python-2.7.15/bin/svtools
        PERL=/usr/bin/perl
        GENOTYPE_VCF=/opt/hall-lab/scripts/vcfToGenotyped.pl
        TABIX=/opt/hall-lab/htslib-1.9/bin/tabix
        $SAMTOOLS view -h ~{alignment} | $K8 $PAFTOOLS sam2paf - | sort -k6,6 -k8,8n | $K8 $PAFTOOLS call -l 1 -L 1 -q 0 - | grep "^V" | sort -V | $BGZIP -c > loose.var.txt.gz
        $PYTHON $VAR_TO_VCF -i <(zcat loose.var.txt.gz) -r ~{ref} -s ~{assembly_name} -o loose.vcf
        $SVTOOLS vcfsort loose.vcf | $PERL $GENOTYPE_VCF | $BGZIP -c > loose.genotyped.vcf.gz
        $TABIX -f -p vcf loose.genotyped.vcf.gz
    >>>
    runtime {
        memory: "64G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File vcf = "loose.genotyped.vcf.gz"
        File vcf_index = "loose.genotyped.vcf.gz.tbi"
    }
}

task align_contigs {
    input {
            File contigs
            File ref
    }
    command <<<
        set -exo pipefail
        MINIMAP2=/opt/hall-lab/minimap2/minimap2
        SAMTOOLS=/opt/hall-lab/samtools-1.9/bin/samtools
        $MINIMAP2 -ax asm5 -L --cs ~{ref} ~{contigs} | $SAMTOOLS sort -T tmp -O bam - > aligned.bam
    >>>
    runtime {
        memory: "64G"
        docker: "apregier/analyze_assemblies@sha256:edf94bd952180acb26423e9b0e583a8b00d658ac533634d59b32523cbd2a602a"
    }
    output {
        File bam = "aligned.bam"
    }
}
