#  Base image 
FROM tensorflow/tensorflow:1.13.1-gpu

# System dependencies
RUN apt-get update && apt-get install -y \
    git wget curl build-essential cmake \
    libgl1-mesa-glx libosmesa6-dev libglib2.0-0 \
    libx11-dev libxcursor-dev libxrandr-dev libxinerama-dev libxi-dev \
    freeglut3-dev unzip patchelf && \
    rm -rf /var/lib/apt/lists/*

# Install Anaconda
RUN wget --quiet https://repo.anaconda.com/archive/Anaconda3-2020.02-Linux-x86_64.sh -O ~/anaconda.sh && \
    /bin/bash ~/anaconda.sh -b -p /opt/conda && \
    rm ~/anaconda.sh
ENV PATH=/opt/conda/bin:$PATH

# Create conda environment with Python 3.6 
RUN conda create -y -n py3-cloth python=3.6
ENV PATH=/opt/conda/envs/py3-cloth/bin:$PATH

# Make conda environment active for every RUN command during image building
SHELL ["conda", "run", "-n", "py3-cloth", "/bin/bash", "-c"]

# Install Blender 2.79
WORKDIR /opt
RUN wget https://download.blender.org/release/Blender2.79/blender-2.79b-linux-glibc219-x86_64.tar.bz2 && \
    tar -xvjf blender-2.79b-linux-glibc219-x86_64.tar.bz2 && \
    rm blender-2.79b-linux-glibc219-x86_64.tar.bz2
ENV PATH="/opt/blender-2.79b-linux-glibc219-x86_64:${PATH}"

COPY ./workspace /workspace

# Clone gym-cloth repository
WORKDIR /workspace
RUN git clone https://github.com/DanielTakeshi/gym-cloth.git
WORKDIR /workspace/gym-cloth

# Upgrade pip and install dependencies
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt && \
    pip install numpy scipy matplotlib opencv-python imageio tqdm gym pyopengl glfw cython

# Build the renderer
WORKDIR /workspace/gym-cloth/render/ext/libzmq
RUN mkdir build && \
    cd build && \ 
    cmake .. && \
    make -j4 install

WORKDIR /workspace/gym-cloth/render/ext/cppzmq
RUN mkdir build && \
    cd build && \
    cmake .. && \
    make -j4 install

#  Fix for header-only cppzmq library (remove invalid link line)
RUN sed -i '/cppzmq/d' /workspace/gym-cloth/render/src/CMakeLists.txt

WORKDIR /workspace/gym-cloth/render
RUN mkdir build && \
    cd build && \
    cmake .. && \
    make -j4

# Build extensions in place to ensure physics module is found
WORKDIR /workspace/gym-cloth
RUN python setup.py build_ext --inplace

WORKDIR /workspace/gym-cloth
RUN python setup.py install

# Clone and install baselines-fork repository
WORKDIR /workspace
RUN git clone https://github.com/DanielTakeshi/baselines-fork.git
WORKDIR /workspace/baselines-fork
RUN pip install -e .

# Fix joblib version compatibility
RUN pip uninstall -y joblib && \
    pip install joblib==1.1.1

# Install TensorFlow GPU to conda environment
RUN pip install tensorflow-gpu==1.13.1

# Initialise conda and activate py3-cloth with every new shell session
RUN conda init bash
RUN echo "conda activate py3-cloth" >> ~/.bashrc

# Environment variables 
ENV PYTHONPATH=/workspace/gym-cloth:/workspace/baselines-fork
ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda-10.0/compat:$LD_LIBRARY_PATH
ENV CONDA_DEFAULT_ENV=py3-cloth

# Default command
CMD ["bash"]
# CMD ["conda", "run", "-n", "py3-cloth", "--no-capture-output", "bash"]
