FROM public.ecr.aws/sam/build-python3.11

LABEL maintainer="Betajob AS" \
      description="Patched AWS Lambda build container"

COPY requirements.txt .

RUN pip install -r requirements.txt

RUN find . -name "*.dist-info" -exec rm -rf {} +