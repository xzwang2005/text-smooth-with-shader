#pragma once
#include "SceneRenderTask.h"

using namespace Glyph3;

class Glyph3::Entity3D;

class FullConnectedInterPixelRenderer :
	public Glyph3::SceneRenderTask
{
public:
	FullConnectedInterPixelRenderer(RendererDX11& Renderer);
	virtual ~FullConnectedInterPixelRenderer();

	virtual void Update(float fTime);
	virtual void QueuePreTasks(RendererDX11* pRenderer);
	virtual void ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager);
	virtual void Resize(UINT width, UINT height);
	virtual void SetRenderParams(IParameterManager* pParamManager);

	void SetTargets(std::vector<ResourcePtr>& renderTargets, ResourcePtr DepthTarget,
		ResourcePtr		discreteSurf, ResourcePtr imageSurf,
		int Viewport);

	virtual std::wstring GetName();

protected:
	RendererDX11&	m_Renderer;
	ResourcePtr		m_DepthTarget;
	std::vector<ResourcePtr>		m_renderTargets;
	ShaderResourceParameterDX11*	m_pImageSurfParam;
	ResourcePtr						m_imageSurf;
	ShaderResourceParameterDX11*	m_pDiscreteSurfParam;
	ResourcePtr						m_DiscreteSurf;
};