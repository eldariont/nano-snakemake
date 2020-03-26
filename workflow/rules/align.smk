localrules: pbmm_index, index_alignment, alignment_stats, pool_samples, subsample_alignments

def get_samples(wildcards):
    return config["samples"][wildcards.sample]


rule run_alignments_minimap2:
    input:
        fq = get_samples,
        genome = config["reference"]
    output:
        temp("pipeline/alignments/{sample}.minimap2.bam")
    params:
        preset = config["parameters"]["minimap_preset"],
        options = config["parameters"]["minimap_options"],
        runtime = "1500",
        memory = "50000"
    threads: 10
    conda:
        "../envs/minimap2.yaml"
    shell:
        "minimap2 -ax {params.preset} {params.options} -t {threads} --MD -Y {input.genome} {input.fq} | \
         samtools sort -@ {threads} -o {output} -"

rule pbmm_index:
    input:
        genome = config["reference"]
    output:
        index = config["reference"] + ".mmi"
    params:
        preset = config["parameters"]["pbmm_preset"]
    threads: 2
    conda:
        "../envs/pbmm2.yaml"
    shell:
        "pbmm2 index --num-threads {threads} --preset {params.preset} \
        {input.genome} {output.index}"

rule run_alignments_pbmm2:
    input:
        fq = get_samples,
        index = config["reference"] + ".mmi"
    output:
        bam = temp("pipeline/alignments/{sample}.pbmm2.bam")
    threads: 10
    params:
        sample = "{sample}",
        preset = config["parameters"]["pbmm_preset"],
        runtime = "1500",
        memory = "50000"
    conda:
        "../envs/pbmm2.yaml"
    shell:
        """
        pbmm2 align --preset {params.preset} -j {threads} \
        --sort --rg '@RG\tID:rg1a\tSM:{params.sample}' --sample HG2 \
        {input.index} {input.fq} {output.bam}
        """

rule run_alignments_ngmlr:
    input:
        fq = get_samples,
        genome = config["reference"]
    output:
        temp("pipeline/alignments/{sample}.ngmlr.bam")
    params:
        preset = config["parameters"]["ngmlr_preset"],
        runtime = "1500",
        memory = "50000"
    threads: 10
    conda:
        "../envs/ngmlr.yaml"
    shell:
        "zcat {input.fq} | \
         ngmlr --presets {params.preset} -t {threads} -r {input.genome} | \
         samtools sort -@ {threads} -o {output} -"

rule index_alignment:
    input:
        "{name}.bam"
    output:
        "{name}.bam.bai"
    threads: 1
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools index {input}"

rule alignment_stats:
    input:
        bam = expand("pipeline/alignments/{sample}.{{aligner}}.bam", sample=config["samples"]),
        bai = expand("pipeline/alignments/{sample}.{{aligner}}.bam.bai", sample=config["samples"])
    output:
        "pipeline/alignment_stats/alignment_stats.{aligner}.txt"
    log:
        "pipeline/logs/alignment_stats/alignment_stats.{aligner}.log"
    shell:
        "python3 workflow/scripts/alignment_stats.py -o {output} {input.bam} 2> {log}"

rule pool_samples:
    input:
        expand("pipeline/alignments/{sample}.{{aligner}}.bam", sample=config["samples"])
    output:
        "pipeline/alignment_pooled/pooled.{aligner}.bam"
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools merge -r {output} {input}"

rule subsample_alignments:
    input:
        "pipeline/alignment_pooled/pooled.{aligner}.bam"
    output:
        "pipeline/alignment_pooled/pooled.subsampled.{fraction,[0-9]+}.{aligner}.bam"
    threads: 4
    params:
        additional_threads = 3
    conda:
        "../envs/samtools.yaml"
    shell:
        "samtools view -s 10.{wildcards.fraction} -@ {params.additional_threads} -b {input} -o {output}"
