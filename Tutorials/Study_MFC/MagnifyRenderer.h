#pragma once
#include "SceneRenderTask.h"
using namespace Glyph3;
class Glyph3::Entity3D;

class MagnifyRenderer :
	public SceneRenderTask
{
public:
	MagnifyRenderer(RendererDX11& Renderer);
	virtual ~MagnifyRenderer();

	virtual void Update(float fTime);
	virtual void QueuePreTasks(RendererDX11* pRenderer);
	virtual void ExecuteTask(PipelineManagerDX11* pPipelineManager, IParameterManager* pParamManager);
	virtual void Resize(UINT width, UINT height);
	virtual void SetRenderParams(IParameterManager* pParamManager);

	void SetTargets(std::vector<ResourcePtr>& renderTargets, ResourcePtr DepthTarget,
		ResourcePtr euclideanSurf,
		ResourcePtr	viewportSurf,
		ResourcePtr fCodeSurf,
		int	magLevel,
		int Viewport);

	virtual std::wstring GetName();

protected:
	RendererDX11&	m_Renderer;
	ResourcePtr		m_DepthTarget;
	std::vector<ResourcePtr>		m_renderTargets;

	ResourcePtr						m_EuclideanSurf;
	ShaderResourceParameterDX11*	m_pEuclideanSurfParam;
	ResourcePtr						m_viewPortSurf;
	ShaderResourceParameterDX11*	m_pViewportSurfParam;

	ResourcePtr						m_fullConnectedSurf;
	ShaderResourceParameterDX11*	m_pFullConnectedSurfParam;

	int								m_magnifyLevel;
	Glyph3::Vector2f				m_magParam;
	Glyph3::VectorParameterDX11*	m_pMagnifyLevelParameter;
};