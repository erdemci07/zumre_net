from reportlab.platypus import KeepTogether, Paragraph, Spacer


def keep_heading_with_first(title: str, first_block, styles):
    return KeepTogether([Paragraph(title, styles["section"]), first_block])


def student_chunks(name: str, flowables: list, styles, chunk_size: int = 16):
    if len(flowables) <= chunk_size:
        return [KeepTogether([Paragraph(name, styles["student"]), *flowables, Spacer(1, 8)])]

    chunks = []
    for index in range(0, len(flowables), chunk_size):
        chunk = flowables[index : index + chunk_size]
        title = name if index == 0 else f"{name} - devam"
        chunks.append(KeepTogether([Paragraph(title, styles["student"]), *chunk, Spacer(1, 8)]))

    return chunks
