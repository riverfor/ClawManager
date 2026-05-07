package services

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"clawreef/internal/repository"
	"clawreef/internal/services/k8s"

	k8sexec "k8s.io/client-go/util/exec"
)

const (
	defaultExecTimeout   = 30 * time.Second
	maxExecTimeout       = 5 * time.Minute
	execOutputCap        = 1 << 20
	defaultExecContainer = "desktop"
)

// InstanceExecRequest carries one-shot exec parameters into InstanceExecService.
type InstanceExecRequest struct {
	Container string
	Command   []string
	Stdin     string
	Timeout   time.Duration
}

// InstanceExecResult is returned for both zero- and non-zero exit codes; only
// transport-level failures surface as a non-nil error from Execute.
type InstanceExecResult struct {
	ExitCode  int
	Stdout    string
	Stderr    string
	Duration  time.Duration
	Truncated bool
}

type InstanceExecService interface {
	Execute(ctx context.Context, instanceID int, req InstanceExecRequest) (*InstanceExecResult, error)
}

type instanceExecService struct {
	instanceRepo repository.InstanceRepository
	podService   *k8s.PodService
}

func NewInstanceExecService(instanceRepo repository.InstanceRepository) InstanceExecService {
	return &instanceExecService{
		instanceRepo: instanceRepo,
		podService:   k8s.NewPodService(),
	}
}

var (
	ErrExecInstanceNotFound   = errors.New("instance not found")
	ErrExecInstanceNotRunning = errors.New("instance is not running")
	ErrExecContainerNotFound  = errors.New("container not found in pod")
	ErrExecEmptyCommand       = errors.New("command must not be empty")
)

func (s *instanceExecService) Execute(ctx context.Context, instanceID int, req InstanceExecRequest) (*InstanceExecResult, error) {
	if len(req.Command) == 0 {
		return nil, ErrExecEmptyCommand
	}

	instance, err := s.instanceRepo.GetByID(instanceID)
	if err != nil {
		return nil, err
	}
	if instance == nil {
		return nil, ErrExecInstanceNotFound
	}
	if instance.Status != "running" {
		return nil, ErrExecInstanceNotRunning
	}

	container := strings.TrimSpace(req.Container)
	if container == "" {
		container = defaultExecContainer
	}

	pod, err := s.podService.GetPod(ctx, instance.UserID, instanceID)
	if err != nil {
		return nil, err
	}
	containerExists := false
	for _, c := range pod.Spec.Containers {
		if c.Name == container {
			containerExists = true
			break
		}
	}
	if !containerExists {
		return nil, fmt.Errorf("%w: %s", ErrExecContainerNotFound, container)
	}

	timeout := req.Timeout
	if timeout <= 0 {
		timeout = defaultExecTimeout
	}
	if timeout > maxExecTimeout {
		timeout = maxExecTimeout
	}

	execCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	stdoutBuf := newCappedBuffer(execOutputCap)
	stderrBuf := newCappedBuffer(execOutputCap)

	var stdin io.Reader
	if req.Stdin != "" {
		stdin = strings.NewReader(req.Stdin)
	}

	start := time.Now()
	execErr := s.podService.Exec(execCtx, instance.UserID, instanceID, k8s.ExecOptions{
		Container: container,
		Command:   req.Command,
		Stdin:     stdin,
		Stdout:    stdoutBuf,
		Stderr:    stderrBuf,
	})
	duration := time.Since(start)

	result := &InstanceExecResult{
		Stdout:    stdoutBuf.String(),
		Stderr:    stderrBuf.String(),
		Duration:  duration,
		Truncated: stdoutBuf.Truncated() || stderrBuf.Truncated(),
	}

	if execErr == nil {
		return result, nil
	}

	var codeErr k8sexec.CodeExitError
	if errors.As(execErr, &codeErr) {
		result.ExitCode = codeErr.Code
		return result, nil
	}

	return nil, execErr
}

// cappedBuffer wraps bytes.Buffer with a hard cap; writes past cap are silently
// dropped after flagging Truncated().
type cappedBuffer struct {
	buf       bytes.Buffer
	cap       int
	truncated bool
}

func newCappedBuffer(cap int) *cappedBuffer { return &cappedBuffer{cap: cap} }

func (b *cappedBuffer) Write(p []byte) (int, error) {
	remaining := b.cap - b.buf.Len()
	if remaining <= 0 {
		b.truncated = true
		return len(p), nil
	}
	if len(p) > remaining {
		b.buf.Write(p[:remaining])
		b.truncated = true
		return len(p), nil
	}
	return b.buf.Write(p)
}

func (b *cappedBuffer) String() string  { return b.buf.String() }
func (b *cappedBuffer) Truncated() bool { return b.truncated }
