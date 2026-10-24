"""Classification endpoints for the Flutter web app.

Media is received as multipart uploads, processed in memory, and never stored.
"""

from typing import Any

from fastapi import APIRouter, File, HTTPException, UploadFile

from ..classifiers import inference

router = APIRouter(prefix="/classify", tags=["classification"])


@router.post("/cough")
async def classify_cough(file: UploadFile = File(...)) -> dict[str, Any]:
    """Run the cough audio classifier on an uploaded audio file."""
    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="Empty file")

    try:
        probs = inference.classify_cough(contents)
        top = max(probs.items(), key=lambda x: x[1])
        return {
            "task": "cough",
            "result": {
                "probabilities": probs,
                "topClass": top[0],
                "topConfidence": top[1],
            },
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Classification failed: {exc}") from exc


@router.post("/{task}")
async def classify_image(task: str, file: UploadFile = File(...)) -> dict[str, Any]:
    """Run an image classifier (rash, wound, face, tongue) on an uploaded image."""
    if task not in ("rash", "wound", "face", "tongue"):
        raise HTTPException(status_code=400, detail=f"Unsupported image task: {task}")

    contents = await file.read()
    if len(contents) == 0:
        raise HTTPException(status_code=400, detail="Empty file")

    try:
        if task == "tongue":
            result = inference.classify_tongue(contents)
        else:
            probs = inference.classify_image(task, contents)
            top = max(probs.items(), key=lambda x: x[1])
            result = {
                "probabilities": probs,
                "topClass": top[0],
                "topConfidence": top[1],
            }
        return {"task": task, "result": result}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Classification failed: {exc}") from exc
